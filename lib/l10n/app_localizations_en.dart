// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get filterBarApply => 'Apply';

  @override
  String get filterBarAddCondition => 'Add condition';

  @override
  String get filterBarAnd => 'AND';

  @override
  String get filterBarOr => 'OR';

  @override
  String get filterBarNoColumns => 'No columns';

  @override
  String get filterBarLoading => 'Loading…';

  @override
  String get mongoAutocompleteTitle => 'Mongo Autocomplete';

  @override
  String get appTitle => 'DbMaster';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsTheme => 'Theme';

  @override
  String get settingsGeneral => 'General';

  @override
  String get settingsConnection => 'Connection';

  @override
  String get settingsEditor => 'Editor';

  @override
  String get settingsAbout => 'About';

  @override
  String get connectionNewConnection => 'New Connection';

  @override
  String get connectionEditConnection => 'Edit Connection';

  @override
  String get connectionManageConnection => 'Manage Connection';

  @override
  String get connectionDeleteConnection => 'Delete Connection';

  @override
  String get connectionConnect => 'Connect';

  @override
  String get connectionCreateDatabase => 'Create Database';

  @override
  String get connectionEnableReadOnly => 'Enable Read-Only';

  @override
  String get connectionDisableReadOnly => 'Disable Read-Only';

  @override
  String connectionMoveToGroup(String groupName) {
    return 'Move to $groupName';
  }

  @override
  String get connectionRemoveFromGroup => 'Remove from Group';

  @override
  String get connectionCollapseAll => 'Collapse All';

  @override
  String get connectionDisconnect => 'Disconnect';

  @override
  String get connectionTestConnection => 'Test Connection';

  @override
  String get connectionConnectionName => 'Connection Name';

  @override
  String get connectionHost => 'Host';

  @override
  String get connectionPort => 'Port';

  @override
  String get connectionUsername => 'Username';

  @override
  String get connectionPassword => 'Password';

  @override
  String get connectionDatabase => 'Database';

  @override
  String get connectionEnvironment => 'Environment';

  @override
  String get connectionEnvironmentNone => 'None';

  @override
  String get commonSave => 'Save';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonEdit => 'Edit';

  @override
  String get commonAdd => 'Add';

  @override
  String get commonClose => 'Close';

  @override
  String get commonDone => 'Done';

  @override
  String get commonSelect => 'Select';

  @override
  String get commonConfirm => 'Confirm';

  @override
  String get commonSearch => 'Search';

  @override
  String get commonRefresh => 'Refresh';

  @override
  String get commonLoading => 'Loading...';

  @override
  String get commonNoData => 'No Data';

  @override
  String get commonSuccess => 'Success';

  @override
  String get commonError => 'Error';

  @override
  String get commonWarning => 'Warning';

  @override
  String get tableNewTable => 'ER Diagram';

  @override
  String get tableEditTable => 'Edit Table';

  @override
  String get tableDeleteTable => 'Delete Table';

  @override
  String get tableTableName => 'Table Name';

  @override
  String get tableColumns => 'Columns';

  @override
  String get tableIndexes => 'Indexes';

  @override
  String get tablePrimaryKey => 'Primary Key';

  @override
  String get tableForeignKey => 'Foreign Key';

  @override
  String get tableRenameTable => 'Rename Table';

  @override
  String get tableNewTableName => 'New table name';

  @override
  String get queryExecute => 'Execute';

  @override
  String get queryExecuteSelected => 'Execute Selected';

  @override
  String get queryFormat => 'Format';

  @override
  String get queryClear => 'Clear';

  @override
  String get queryHistory => 'Query History';

  @override
  String get queryResults => 'Results';

  @override
  String get sidebarConnections => 'Connections';

  @override
  String get sidebarDatabases => 'Databases';

  @override
  String get sidebarTables => 'Tables';

  @override
  String get sidebarKeys => 'Keys';

  @override
  String get sidebarCollections => 'Collections';

  @override
  String get sidebarSuperTables => 'SuperTables';

  @override
  String get sidebarViews => 'Views';

  @override
  String get sidebarSavedQueries => 'Saved Queries';

  @override
  String get sidebarProcedures => 'Stored Procedures';

  @override
  String get sidebarTriggers => 'Triggers';

  @override
  String get sidebarFunctions => 'Functions';

  @override
  String get sidebarServer => 'Server';

  @override
  String get sidebarProcessList => 'Process List';

  @override
  String get sidebarServerStatus => 'Server Status';

  @override
  String get sidebarNoUsers => 'No users';

  @override
  String get sidebarNoActiveProcesses => 'No active processes';

  @override
  String sidebarTdColsTags(int cols, int tags) {
    return '$cols cols, $tags tags';
  }

  @override
  String sidebarTdColumnsCount(int count) {
    return 'Columns ($count)';
  }

  @override
  String sidebarTdTagsCount(int count) {
    return 'Tags ($count)';
  }

  @override
  String get sidebarTdDeleteTitle => 'Delete SuperTable';

  @override
  String sidebarTdDeleteConfirm(String name) {
    return 'Are you sure you want to delete SuperTable \"$name\"?\n\nThis will also delete all its SubTables!';
  }

  @override
  String get sidebarDeleteGroup => 'Delete Group';

  @override
  String get sidebarDeleteGroupPrompt => 'Select a group to delete:';

  @override
  String get sidebarConnectionSwitch => 'Switch connection';

  @override
  String get sidebarSelectConnectionHint =>
      'Select a connection from the picker above to start';

  @override
  String get sidebarConnectionNone => 'No connection';

  @override
  String get sidebarManageConnections => 'Manage Connections…';

  @override
  String get sidebarExtensions => 'Extensions';

  @override
  String get noExtensionsInstalled => 'No extensions installed';

  @override
  String get sidebarSchemas => 'Schemas';

  @override
  String get sidebarMaterializedViews => 'Materialized Views';

  @override
  String get sidebarSequences => 'Sequences';

  @override
  String get settingsGeneralSettings => 'General Settings';

  @override
  String get settingsAppearanceSettings => 'Appearance';

  @override
  String get settingsEditorSettings => 'Editor Settings';

  @override
  String get settingsEnableAutocomplete => 'Enable Autocomplete';

  @override
  String get settingsAutocompleteDescription =>
      'Automatically suggest SQL keywords and table names';

  @override
  String get settingsSqlCoolTheme => 'SQL Cool Theme';

  @override
  String get settingsSqlCoolThemeDesc =>
      'Use the cool syntax palette (matches the app shell). Turn off for the platform default palette.';

  @override
  String get safetyRulesSectionTitle => 'Safety Rules';

  @override
  String get safetyRuleSchemaCompat => 'Schema Compatibility';

  @override
  String get safetyRuleSchemaCompatDesc =>
      'Check referenced columns exist in the table before execution';

  @override
  String get safetyRuleMissingLimit => 'Missing LIMIT Warning';

  @override
  String get safetyRuleMissingLimitDesc =>
      'Warn when querying large tables without a LIMIT clause';

  @override
  String get safetyRuleFullTableScan => 'Full Table Scan (Static)';

  @override
  String get safetyRuleFullTableScanDesc =>
      'Detect index-breaking patterns in WHERE clauses (e.g. function-wrapped columns)';

  @override
  String get safetyRuleSqlInjection => 'SQL Injection Detection';

  @override
  String get safetyRuleSqlInjectionDesc =>
      'Flag common SQL injection patterns (tautologies, comment truncation)';

  @override
  String get safetyRuleExplainFullScan => 'Full Table Scan (EXPLAIN)';

  @override
  String get safetyRuleExplainFullScanDesc =>
      'Run EXPLAIN to detect actual full table scans chosen by the optimizer';

  @override
  String get safetyRuleExplainEstimatedRows =>
      'Large Result Set Warning (EXPLAIN)';

  @override
  String get safetyRuleExplainEstimatedRowsDesc =>
      'Run EXPLAIN to warn when estimated returned rows exceed the threshold';

  @override
  String get safetyRuleExecutableComment => 'MySQL Executable Comments';

  @override
  String get safetyRuleExecutableCommentDesc =>
      'Detect statements hidden in /*! ... */ version comments (executed by MySQL)';

  @override
  String get safetyRuleTautologyPredicate => 'Tautology Predicates';

  @override
  String get safetyRuleTautologyPredicateDesc =>
      'Detect always-true WHERE conditions such as 1=1, TRUE, and self-comparisons';

  @override
  String get safetyRuleComplementaryOr => 'Complementary OR Branches';

  @override
  String get safetyRuleComplementaryOrDesc =>
      'Detect complementary always-true OR branches such as x IS NULL OR x IS NOT NULL';

  @override
  String get safetyRuleWritableCte => 'Writable CTEs';

  @override
  String get safetyRuleWritableCteDesc =>
      'Detect DELETE/UPDATE/INSERT embedded in WITH clause CTE bodies';

  @override
  String get safetyRuleFileWrite => 'Filesystem Access';

  @override
  String get safetyRuleFileWriteDesc =>
      'Detect INTO OUTFILE/DUMPFILE and LOAD_FILE server file access';

  @override
  String get safetyRuleReviewFailClosed => 'Fail-Closed for Writes';

  @override
  String get safetyRuleReviewFailClosedDesc =>
      'Warn on write statements when safety review degrades (reads pass through)';

  @override
  String get safetyFullScanThreshold =>
      'Row count threshold (missing LIMIT / full scan / large result)';

  @override
  String get settingsAiSettings => 'AI Settings';

  @override
  String get settingsAutoExecuteSql => 'Auto Execute SQL';

  @override
  String get settingsAutoExecuteSqlDescription =>
      'Automatically execute SQL when a tab is opened';

  @override
  String get settingsThemeSettings => 'Theme';

  @override
  String get settingsDarkMode => 'Dark';

  @override
  String get settingsLightMode => 'Light';

  @override
  String get shortcutCategoryFile => 'File';

  @override
  String get shortcutCategoryEdit => 'Edit';

  @override
  String get shortcutCategoryView => 'View';

  @override
  String get shortcutCategoryAi => 'AI';

  @override
  String get shortcutCategoryTab => 'Tabs';

  @override
  String get shortcutNewConnection => 'New Connection';

  @override
  String get shortcutNewTab => 'New Tab';

  @override
  String get shortcutCloseTab => 'Close Tab';

  @override
  String get shortcutSaveQuery => 'Save Query';

  @override
  String get shortcutExportData => 'Export Data';

  @override
  String get shortcutExecuteQuery => 'Execute Query';

  @override
  String get shortcutExecuteQueryNewTab => 'Execute Query in New Tab';

  @override
  String get shortcutFormatSql => 'Format SQL';

  @override
  String get shortcutFind => 'Find';

  @override
  String get shortcutReplace => 'Replace';

  @override
  String get shortcutAutocomplete => 'Autocomplete';

  @override
  String get shortcutUndo => 'Undo';

  @override
  String get shortcutRedo => 'Redo';

  @override
  String get shortcutToggleSidebar => 'Toggle Sidebar';

  @override
  String get shortcutToggleAiPanel => 'Toggle AI Panel';

  @override
  String get shortcutCommandPalette => 'Command Palette';

  @override
  String get shortcutShortcutHelp => 'Keyboard Shortcuts';

  @override
  String get shortcutGenerateSql => 'Generate SQL';

  @override
  String get shortcutOptimizeSql => 'Optimize SQL';

  @override
  String get shortcutExplainSql => 'Explain SQL';

  @override
  String get shortcutNextTab => 'Next Tab';

  @override
  String get shortcutPreviousTab => 'Previous Tab';

  @override
  String get shortcutSwitchToTab => 'Switch to Tab';

  @override
  String get shortcutToggleAiFullscreen => 'AI Panel Fullscreen';

  @override
  String get shortcutAuditLog => 'Query Audit Log';

  @override
  String get shortcutIncreaseOpacity => 'Increase Overlay Opacity';

  @override
  String get shortcutDecreaseOpacity => 'Decrease Overlay Opacity';

  @override
  String get tableCreateNewTable => 'Create New Table';

  @override
  String get toolbarBackup => 'Backup';

  @override
  String get toolbarImport => 'Import';

  @override
  String get toolbarExport => 'Export';

  @override
  String get sidebarExpand => 'Expand';

  @override
  String get sidebarSettings => 'Settings';

  @override
  String get sidebarSearchHint => 'Search connections, tables, views...';

  @override
  String sidebarConnectionActive(Object count) {
    return '$count connections active';
  }

  @override
  String get sidebarNoConnections => 'No saved connections';

  @override
  String get sidebarClickToCreateConnection =>
      'Click the button below to create a connection';

  @override
  String get sidebarCreateConnection => 'Create Connection';

  @override
  String get resultsExport => 'Export';

  @override
  String get resultsSave => 'Save';

  @override
  String get resultsDiscard => 'Discard';

  @override
  String get resultsNoDataToExport => 'No data to export';

  @override
  String get cellEditNotSupported =>
      'Cell editing is not available yet — edits cannot be saved back to the database';

  @override
  String get exportExcelGenerating => 'Generating Excel…';

  @override
  String get resultsCSV => 'CSV';

  @override
  String get resultsJSON => 'JSON';

  @override
  String get resultsExcel => 'Excel';

  @override
  String get resultsConfirmDiscardChanges => 'Confirm Discard Changes';

  @override
  String resultsDiscardChangesMessage(Object count) {
    return 'Are you sure you want to discard $count changes? This action cannot be undone.';
  }

  @override
  String get resultsContinueEditing => 'Continue Editing';

  @override
  String get resultsDiscardChanges => 'Discard Changes';

  @override
  String get resultsConfirmExecuteSQL => 'Confirm Execute SQL';

  @override
  String get resultsBarChart => 'Bar Chart';

  @override
  String get resultsLineChart => 'Line Chart';

  @override
  String get resultsPieChart => 'Pie Chart';

  @override
  String get resultsSelectAxisFields =>
      'Please select X-axis and Y-axis fields';

  @override
  String get statusNotConnected => 'Not Connected';

  @override
  String get statusConnected => 'Connected';

  @override
  String statusTables(Object count) {
    return '$count Tables';
  }

  @override
  String get statusNone => 'None';

  @override
  String statusVersion(Object version) {
    return 'v$version';
  }

  @override
  String get backupManagement => 'Backup Management';

  @override
  String get backupList => 'Backup List';

  @override
  String get createBackup => 'Create Backup';

  @override
  String get noBackupFiles => 'No backup files';

  @override
  String get clickCreateBackupTab =>
      'Click the Create Backup tab to get started';

  @override
  String get importBackup => 'Import Backup';

  @override
  String get previewContent => 'Preview Content';

  @override
  String get exportFile => 'Export File';

  @override
  String get restoreBackup => 'Restore Backup';

  @override
  String get selectBackupToView => 'Select a backup to view details';

  @override
  String get database => 'Database';

  @override
  String get backupType => 'Type';

  @override
  String get backupSize => 'Size';

  @override
  String get createdAt => 'Created At';

  @override
  String get tableCount => 'Table Count';

  @override
  String get description => 'Description';

  @override
  String get preview => 'Preview';

  @override
  String get export => 'Export';

  @override
  String get restore => 'Restore';

  @override
  String get confirmRestore => 'Confirm Restore';

  @override
  String confirmRestoreMessage(Object name) {
    return 'Are you sure you want to restore backup \"$name\"?\n\nThis will execute all SQL statements in the backup file and may overwrite existing data.';
  }

  @override
  String get confirmDelete => 'Confirm Delete';

  @override
  String confirmDeleteMessage(Object name) {
    return 'Are you sure you want to delete backup \"$name\"?\n\nThis action cannot be undone.';
  }

  @override
  String get backupFormat => 'Backup Format';

  @override
  String get backupContent => 'Backup Content';

  @override
  String get selectTablesHint => 'Select Tables (leave empty for all)';

  @override
  String get advancedOptions => 'Advanced Options';

  @override
  String get includeStructure => 'Include Table Structure';

  @override
  String get includeStructureDesc => 'CREATE TABLE statements';

  @override
  String get includeData => 'Include Data';

  @override
  String get includeDataDesc => 'INSERT statements or data rows';

  @override
  String get noTablesAvailable => 'No tables available';

  @override
  String get selectAll => 'Select All';

  @override
  String get deselectAll => 'Deselect All';

  @override
  String tablesSelected(Object count) {
    return '$count tables selected';
  }

  @override
  String get addDropTable => 'Add DROP TABLE';

  @override
  String get useExtendedInsert => 'Use Extended INSERT';

  @override
  String get useExtendedInsertDesc => 'Combine multiple rows into one INSERT';

  @override
  String get rowLimitPerTable => 'Row Limit Per Table (optional)';

  @override
  String get leaveEmptyForNoLimit => 'Leave empty for no limit';

  @override
  String get whereCondition => 'WHERE Condition (optional)';

  @override
  String get whereConditionExample => 'e.g.: id > 100';

  @override
  String get enterBackupDescription => 'Enter backup description (optional)';

  @override
  String get startBackup => 'Start Backup';

  @override
  String get backupProgress => 'Backup Progress';

  @override
  String get waitingToStartBackup => 'Waiting to start backup...';

  @override
  String get currentTable => 'Current Table';

  @override
  String get progressPercent => 'Progress';

  @override
  String get backupComplete => 'Backup Complete!';

  @override
  String get backupFailed => 'Backup Failed';

  @override
  String get loadBackupListFailed => 'Unable to load backup list';

  @override
  String get retry => 'Retry';

  @override
  String get previewFailed => 'Preview failed';

  @override
  String get exportedTo => 'Exported to';

  @override
  String get backupRestoreSuccess => 'Backup restored successfully';

  @override
  String get restoreFailed => 'Restore failed';

  @override
  String get backupDeleted => 'Backup deleted';

  @override
  String deleteFailed(Object error) {
    return 'Deletion failed: $error';
  }

  @override
  String get selectBackupFile => 'Select Backup File';

  @override
  String get backupImportSuccess => 'Backup file imported successfully';

  @override
  String importFailed(String error) {
    return 'Import failed: $error';
  }

  @override
  String get selectAtLeastOneOption =>
      'Please select at least one option (structure or data)';

  @override
  String get backupFailedError => 'Backup failed';

  @override
  String get aiAssistant => 'AI Assistant';

  @override
  String get aiAnalyze => 'AI Analyze';

  @override
  String get aiAnalyzeTable => 'AI Analyze Table';

  @override
  String get aiAnalyzeDatabase => 'AI Analyze Database';

  @override
  String get aiAnalyzeServer => 'AI Analyze Server';

  @override
  String get aiAnalyzeErrorResult => 'AI Analyze Error';

  @override
  String aiAnalyzeNodeFailed(Object error) {
    return 'AI analysis failed: $error';
  }

  @override
  String get apiSettings => 'API Settings';

  @override
  String get clearChat => 'Clear Chat';

  @override
  String get model => 'Model';

  @override
  String get enterModelName => 'Enter model name';

  @override
  String get autoExecuteSql => 'Auto Execute SQL';

  @override
  String get autoExecuteSqlDesc =>
      'When enabled, AI-generated queries will be executed automatically';

  @override
  String get aiDatabaseAssistant => 'AI Database Assistant';

  @override
  String get aiAssistantDesc =>
      'Supports multiple AI providers\nHelps you write SQL, optimize queries, explain database structure';

  @override
  String get enterYourQuestion => 'Enter your question...';

  @override
  String configureApiKeyFirst(Object provider) {
    return 'Please configure the API key for $provider in Settings first.\n\nClick the settings icon in the top right corner to get started.';
  }

  @override
  String get generationFailed => 'Generation failed';

  @override
  String get stepAnalyzeNeeds =>
      'Step 1: Analyzing user needs, determining tables to query...';

  @override
  String get stepGetTableSchema => 'Step 2: Getting detailed table schemas...';

  @override
  String get stepGenerateSql => 'Step 3: Generating SQL statements...';

  @override
  String get analysisResultTables => 'Analysis Result: Tables to query';

  @override
  String get tableSchemaInfo => 'Table Schema Information';

  @override
  String get operationCancelled => 'Operation cancelled';

  @override
  String get executingSql => 'Executing SQL...';

  @override
  String executeSuccessRows(Object count) {
    return 'Execution successful. $count rows returned.';
  }

  @override
  String get executeFailedError => 'Execution failed';

  @override
  String get confirmDangerousOperation => 'Confirm Dangerous Operation?';

  @override
  String get confirmExecuteSql => 'Confirm Execute SQL';

  @override
  String get dangerousOperationWarning =>
      'This operation may modify or delete data. Please proceed with caution!';

  @override
  String get sqlCopied => 'SQL copied';

  @override
  String get sqlGenerationComplete => 'SQL Generation Complete';

  @override
  String get dangerousOperation => 'Dangerous Operation';

  @override
  String get dangerousOperationDesc =>
      'This is a dangerous operation. Please handle with care.';

  @override
  String get taskCompleteDesc =>
      'Task completed. You can choose to execute or copy the SQL.';

  @override
  String get generatedSql => 'Generated SQL';

  @override
  String get dangerous => 'Dangerous';

  @override
  String get confirmExecute => 'Confirm Execute';

  @override
  String get requestTimeout => 'Request Timeout';

  @override
  String get seconds => 'seconds';

  @override
  String get apiSettingsSaved => 'API settings saved';

  @override
  String get dataImport => 'Data Import';

  @override
  String get selectFile => 'Select File';

  @override
  String get noFileSelected => 'No file selected';

  @override
  String get importConfig => 'Import Configuration';

  @override
  String get targetTableName => 'Target Table Name';

  @override
  String get enterTableName => 'Enter table name';

  @override
  String get includeHeader => 'Include Header';

  @override
  String get delimiter => 'Delimiter';

  @override
  String get overwriteTable => 'Overwrite Table';

  @override
  String get deleteExistingTable => '(Delete existing table)';

  @override
  String get batchSize => 'Batch Size';

  @override
  String dataPreviewRows(Object count) {
    return 'Data Preview ($count rows)';
  }

  @override
  String get pleaseSelectFile => 'Please select a file to preview the data';

  @override
  String get importProgress => 'Import Progress';

  @override
  String get importPreparing => 'Preparing import...';

  @override
  String get totalRecords => 'Total';

  @override
  String get importedRecords => 'Imported';

  @override
  String get failedRecords => 'Failed';

  @override
  String get readyToImport => 'Ready to import';

  @override
  String get importingData => 'Importing data...';

  @override
  String get importComplete => 'Import complete!';

  @override
  String get parseFileFailed => 'Failed to parse file';

  @override
  String get noDataToImport => 'No data to import';

  @override
  String get selectDatabaseFirst => 'Please select a database first';

  @override
  String get importFailedError => 'Import failed';

  @override
  String get startImport => 'Start Import';

  @override
  String get importing => 'Importing...';

  @override
  String get optimizeSql => 'Optimize SQL';

  @override
  String get explainQuery => 'Explain Query';

  @override
  String get generateInsert => 'Generate INSERT';

  @override
  String get generateUpdate => 'Generate UPDATE';

  @override
  String get generateDelete => 'Generate DELETE';

  @override
  String get createTableStatement => 'Create Table Statement';

  @override
  String get securityCheck => 'Security Check';

  @override
  String get indexSuggestion => 'Index Suggestion';

  @override
  String get executionPlan => 'Execution Plan';

  @override
  String get pleaseEnterSql => 'Please enter an SQL statement first';

  @override
  String get pleaseConnectDatabase => 'Please connect to a database first';

  @override
  String get analysisFailed => 'Analysis failed';

  @override
  String get loadHistoryFailed => 'Unable to load query history';

  @override
  String get noQueryHistory =>
      'No query history yet\n\nAfter executing SQL queries, history will be saved here.';

  @override
  String queryHistoryRecords(Object count) {
    return 'Query History (Recent $count records)';
  }

  @override
  String get databaseType => 'Database Type';

  @override
  String get server => 'Server';

  @override
  String get currentDatabase => 'Current Database';

  @override
  String get notConnected => 'Not Connected';

  @override
  String get notSelected => 'Not Selected';

  @override
  String get tableName => 'Table Name';

  @override
  String get tableStructureInfo => 'Table Structure Information';

  @override
  String get createStatement => 'Create Statement';

  @override
  String andMoreTables(Object count) {
    return '... and $count more tables';
  }

  @override
  String get primaryKey => 'Primary Key';

  @override
  String get executionTime => 'Execution Time';

  @override
  String get status => 'Status';

  @override
  String get commonFailed => 'Failed';

  @override
  String get format => 'Format';

  @override
  String get connectionDefaultDatabase => 'Default Database';

  @override
  String get connectionSavePassword => 'Save Password';

  @override
  String get connectionAdvancedOptions => 'Advanced Options';

  @override
  String get connectionTimeout => 'Timeout (seconds)';

  @override
  String get connectionUseSSL => 'Use SSL/TLS';

  @override
  String get connectionEnableSecureConnection => 'Enable secure connection';

  @override
  String get connectionUseTls => 'Use TLS/SSL';

  @override
  String get connectionUseTlsDesc =>
      'Encrypt the connection via TLS (established on the server side)';

  @override
  String get connectionTlsInsecure => 'Skip certificate verification (unsafe)';

  @override
  String get connectionTlsInsecureDesc =>
      'Do not verify the server certificate — trusted/test environments only';

  @override
  String get connectionSshSubtitleGateway =>
      'SSH tunnel established by the dbmaster server (config travels with the connection)';

  @override
  String get connectionAutoReconnect => 'Auto Reconnect';

  @override
  String get connectionAutoReconnectDesc =>
      'Automatically try to reconnect when connection is lost';

  @override
  String get connectionCharset => 'Character Set';

  @override
  String get connectionTimezone => 'Time Zone';

  @override
  String get connectionTestSuccess => 'Connection successful!';

  @override
  String connectionTestFailed(String error) {
    return 'Test failed: $error';
  }

  @override
  String get connectionDatabaseType => 'Database Type';

  @override
  String get connectionManager => 'Connection Manager';

  @override
  String get connectionSavedConnections => 'Saved Connections';

  @override
  String get connectionNoSavedConnections => 'No saved connections';

  @override
  String get connectionCurrent => 'Current';

  @override
  String get connectionConnected => 'Connected';

  @override
  String get connectionSwitchToConnection => 'Switch to this connection';

  @override
  String get connectionCloneConnection => 'Clone Connection';

  @override
  String get connectionCloned => 'Connection cloned';

  @override
  String get connectionDeleteConnectionTitle => 'Delete Connection';

  @override
  String get connectionDeleteConnectionConfirm =>
      'Are you sure you want to delete connection';

  @override
  String get connectionDisconnectAll => 'Disconnect All';

  @override
  String get searchDialogTitle => 'Search';

  @override
  String get searchHint =>
      'Search tables, views, stored procedures, columns...';

  @override
  String get searchNoResults => 'No objects found';

  @override
  String get searchTryDifferentKeywords => 'Try different keywords';

  @override
  String get searchNavigate => 'Navigate';

  @override
  String get searchSelect => 'Select';

  @override
  String get searchClose => 'Close';

  @override
  String searchResultsCount(Object count) {
    return '$count results';
  }

  @override
  String get searchTypeConnection => 'Connection';

  @override
  String get searchTypeDatabase => 'Database';

  @override
  String get searchTypeTable => 'Table';

  @override
  String get searchTypeView => 'View';

  @override
  String get searchTypeProcedure => 'Procedure';

  @override
  String get searchTypeColumn => 'Column';

  @override
  String get savedQueriesTitle => 'Saved Queries';

  @override
  String get savedQueriesNoQueries => 'No saved queries';

  @override
  String get savedQueriesDeleteTitle => 'Delete Query';

  @override
  String get savedQueriesDeleteConfirm =>
      'Are you sure you want to delete this query?';

  @override
  String get savedQueriesOpen => 'Open';

  @override
  String get viewJson => 'View JSON';

  @override
  String get extractFieldAsColumn => 'Extract field as column';

  @override
  String get erDiagramTitle => 'ER Diagram';

  @override
  String get erDiagramSearchTables => 'Search tables...';

  @override
  String get erDiagramHierarchicalLayout => 'Hierarchical Layout';

  @override
  String get erDiagramForceDirectedLayout => 'Force Directed Layout';

  @override
  String get erDiagramCircleLayout => 'Circle Layout';

  @override
  String get erDiagramResetLayout => 'Reset Layout';

  @override
  String get erDiagramZoomIn => 'Zoom In';

  @override
  String get erDiagramZoomOut => 'Zoom Out';

  @override
  String get erDiagramFitToScreen => 'Fit to Screen';

  @override
  String get erDiagramRelations => 'Relations';

  @override
  String get erDiagramZoom => 'Zoom';

  @override
  String get erDiagramShowIsolated => 'Show Isolated';

  @override
  String get erDiagramExportAsPNG => 'Export as PNG';

  @override
  String get erDiagramExportAsJPG => 'Export as JPG';

  @override
  String get erDiagramLoading => 'Loading ER Diagram...';

  @override
  String get erDiagramErrorLoading => 'Error loading ER Diagram';

  @override
  String get erDiagramNoData => 'No diagram data available';

  @override
  String get erDiagramRetry => 'Retry';

  @override
  String get erDiagramSelectConnection => 'Select Connection';

  @override
  String get erDiagramSelectDatabase => 'Select Database';

  @override
  String get performanceAnalyzerTitle => 'Performance Analyzer';

  @override
  String get performanceAnalyzerSearch => 'Search...';

  @override
  String get performanceAnalyzerRefresh => 'Refresh Data';

  @override
  String get performanceAnalyzerGenerateReport => 'Generate Report';

  @override
  String get performanceAnalyzerExport => 'Export';

  @override
  String get performanceAnalyzerClose => 'Close';

  @override
  String get performanceAnalyzerNotConnected => 'Not Connected to Database';

  @override
  String get performanceAnalyzerNotConnectedDesc =>
      'Please connect to a database first to use performance analysis';

  @override
  String get performanceAnalyzerConfirm => 'Confirm';

  @override
  String get performanceAnalyzerSlowQueryAnalysis => 'Slow Query Analysis';

  @override
  String get performanceAnalyzerIndexAnalysis => 'Index Analysis';

  @override
  String get performanceAnalyzerTableStatistics => 'Table Statistics';

  @override
  String get performanceAnalyzerPerformanceReport => 'Performance Report';

  @override
  String get performanceAnalyzerLoading => 'Analyzing database performance...';

  @override
  String get performanceAnalyzerLoadFailed => 'Load Failed';

  @override
  String get performanceAnalyzerRetry => 'Retry';

  @override
  String get performanceAnalyzerTimeThreshold => 'Time Threshold:';

  @override
  String get performanceAnalyzerNoSlowQueries => 'No slow queries found';

  @override
  String get performanceAnalyzerSelectQuery => 'Select a query to view details';

  @override
  String get performanceAnalyzerQueryInfo => 'Query Information';

  @override
  String get performanceAnalyzerExecutionTime => 'Execution Time';

  @override
  String get performanceAnalyzerDatabase => 'Database';

  @override
  String get performanceAnalyzerRowsScaned => 'Rows Scanned';

  @override
  String get performanceAnalyzerRowsReturned => 'Rows Returned';

  @override
  String get performanceAnalyzerTimestamp => 'Execution Time';

  @override
  String get performanceAnalyzerSqlStatement => 'SQL Statement';

  @override
  String get performanceAnalyzerExecutionPlan => 'Execution Plan';

  @override
  String get performanceAnalyzerOptimizationSuggestions =>
      'Optimization Suggestions';

  @override
  String get performanceAnalyzerFullTableScan => 'Full Table Scan Detected';

  @override
  String get performanceAnalyzerFullTableScanDesc =>
      'Query uses full table scan (type=ALL), consider adding index on WHERE clause columns';

  @override
  String get performanceAnalyzerFileSort => 'File Sort';

  @override
  String get performanceAnalyzerFileSortDesc =>
      'Query uses file sort (Using filesort), consider adding index on ORDER BY columns';

  @override
  String get performanceAnalyzerTempTable => 'Temporary Table Usage';

  @override
  String get performanceAnalyzerTempTableDesc =>
      'Query uses temporary table (Using temporary), consider optimizing GROUP BY or DISTINCT queries';

  @override
  String get performanceAnalyzerLowScanEfficiency => 'Low Scan Efficiency';

  @override
  String get performanceAnalyzerNoIssues => 'No Obvious Issues';

  @override
  String get performanceAnalyzerNoIssuesDesc =>
      'Query execution plan looks normal';

  @override
  String get performanceAnalyzerIndexTypeDistribution =>
      'Index Type Distribution';

  @override
  String get performanceAnalyzerNoData => 'No Data';

  @override
  String get performanceAnalyzerTotalIndexes => 'Total Indexes';

  @override
  String get performanceAnalyzerUsedIndexes => 'Used';

  @override
  String get performanceAnalyzerUnusedIndexes => 'Unused';

  @override
  String get performanceAnalyzerIndexes => 'indexes';

  @override
  String get performanceAnalyzerColumns => 'Columns:';

  @override
  String get performanceAnalyzerCardinality => 'Cardinality:';

  @override
  String get performanceAnalyzerTotalTables => 'Total Tables';

  @override
  String get performanceAnalyzerTotalRows => 'Total Rows';

  @override
  String get performanceAnalyzerDataSize => 'Data Size';

  @override
  String get performanceAnalyzerIndexSize => 'Index Size';

  @override
  String get performanceAnalyzerTotalSize => 'Total Size';

  @override
  String get performanceAnalyzerTableName => 'Table Name';

  @override
  String get performanceAnalyzerEngine => 'Engine';

  @override
  String get performanceAnalyzerRowCount => 'Row Count';

  @override
  String get performanceAnalyzerPercentage => 'Percentage';

  @override
  String get performanceAnalyzerTableSizeDistribution =>
      'Table Size Distribution (Top 10)';

  @override
  String get performanceAnalyzerDatabasePerformanceReport =>
      'Database Performance Report';

  @override
  String get performanceAnalyzerGeneratedAt => 'Generated At:';

  @override
  String get performanceAnalyzerTableCount => 'Table Count';

  @override
  String get performanceAnalyzerSlowQueries => 'Slow Queries';

  @override
  String get performanceAnalyzerSuggestions => 'Suggestions';

  @override
  String get performanceAnalyzerImpact => 'Impact:';

  @override
  String get performanceAnalyzerImpactHigh => 'High';

  @override
  String get performanceAnalyzerImpactMedium => 'Medium';

  @override
  String get performanceAnalyzerImpactLow => 'Low';

  @override
  String get performanceAnalyzerRecommendation => 'Recommendation:';

  @override
  String get performanceAnalyzerSlowQueriesTop => 'Slow Queries Top';

  @override
  String get performanceAnalyzerLargeTableStatistics =>
      'Large Table Statistics';

  @override
  String get performanceAnalyzerClickGenerateReport =>
      'Click \"Generate Report\" button to start analysis';

  @override
  String get sqlHistoryTitle => 'SQL History';

  @override
  String get sqlHistoryNoHistory => 'No history yet';

  @override
  String get sqlHistoryClose => 'Close';

  @override
  String get sqlHistoryDelete => 'Delete';

  @override
  String get sqlHistoryConfirmDelete => 'Confirm Delete';

  @override
  String get sqlHistoryDeleteConfirm =>
      'Are you sure you want to delete this history record?';

  @override
  String get sqlHistoryJustNow => 'Just now';

  @override
  String sqlHistoryMinutesAgo(Object count) {
    return '$count minutes ago';
  }

  @override
  String sqlHistoryHoursAgo(Object count) {
    return '$count hours ago';
  }

  @override
  String sqlHistoryDaysAgo(Object count) {
    return '$count days ago';
  }

  @override
  String get aiPanelApiSettings => 'API Settings';

  @override
  String get aiPanelApiKey => 'API Key';

  @override
  String get aiPanelEnterApiKey => 'Enter API key';

  @override
  String get aiPanelApiBaseUrl => 'API Base URL (optional)';

  @override
  String get aiPanelCustomApiUrl => 'Custom API URL';

  @override
  String get aiPanelRequestTimeout => 'Request Timeout:';

  @override
  String get aiPanelSeconds => 'seconds';

  @override
  String get aiPanelSave => 'Save';

  @override
  String get aiPanelApiSettingsSaved => 'API settings saved';

  @override
  String get aiPanelConfirmDangerousOperation => 'Confirm Dangerous Operation?';

  @override
  String get aiPanelConfirmExecuteSql => 'Confirm Execute SQL';

  @override
  String get aiPanelDangerousOperationWarning =>
      'This operation may modify or delete data. Please proceed with caution!';

  @override
  String get aiPanelCancel => 'Cancel';

  @override
  String get aiPanelConfirmExecute => 'Confirm Execute';

  @override
  String get aiPanelOperationCancelled => 'Operation cancelled';

  @override
  String get aiPanelExecutingSql => 'Executing SQL...';

  @override
  String aiPanelExecuteSuccess(Object count) {
    return 'Execution successful. $count rows returned.';
  }

  @override
  String get aiPanelExecuteFailed => 'Execution failed';

  @override
  String get aiPanelDataPreview => 'Data Preview';

  @override
  String aiPanelAndMoreRows(Object count) {
    return 'and $count more rows';
  }

  @override
  String aiPanelSqlExecutionSuccess(Object count) {
    return 'SQL executed successfully. $count rows returned.';
  }

  @override
  String get aiPanelSqlGenerationComplete => 'SQL Generation Complete';

  @override
  String get aiPanelSqlGenerationCompleteWarning =>
      'SQL Generation Complete ⚠️';

  @override
  String get aiPanelTaskCompleteDesc =>
      'Task completed. You can choose to execute or copy the SQL.';

  @override
  String get aiPanelDangerousOperationDesc =>
      'This is a dangerous operation. Please handle with care.';

  @override
  String get aiPanelGeneratedSql => 'Generated SQL';

  @override
  String get aiPanelDangerous => 'Dangerous';

  @override
  String get aiPanelContinue => 'Continue';

  @override
  String get aiPanelClose => 'Close';

  @override
  String get aiPanelCopy => 'Copy';

  @override
  String get aiPanelExecute => 'Execute';

  @override
  String get aiPanelConfirmExecuteDangerous => 'Confirm Execute';

  @override
  String get quickActionsTitle => 'Quick Actions';

  @override
  String get quickActionsNewTable => 'New Table';

  @override
  String get quickActionsNewQuery => 'New Query';

  @override
  String get quickActionsAiAssistant => 'AI Assistant';

  @override
  String get quickActionsSelectDatabaseFirst =>
      'Please select a database first';

  @override
  String get resultsTabResults => 'Results';

  @override
  String get resultsTabMessages => 'Messages';

  @override
  String get resultsTabExecutionPlan => 'Execution Plan';

  @override
  String get resultsTabExecutionDetails => 'Execution Details';

  @override
  String get resultsSearchBtn => 'Search';

  @override
  String get resultsSearchHint => 'Search in results…';

  @override
  String resultsSearchNoMatch(Object query) {
    return 'No rows match \"$query\"';
  }

  @override
  String get resultsClear => 'Clear';

  @override
  String get resultsSubmit => 'Submit';

  @override
  String get resultsSearchResults => 'Search Results';

  @override
  String get resultsViewTable => 'Table';

  @override
  String get resultsViewCard => 'Card';

  @override
  String get resultsViewChart => 'Chart';

  @override
  String get resultsViewStatistics => 'Statistics';

  @override
  String get paginationShowing => 'Showing';

  @override
  String get paginationRows => 'of';

  @override
  String get paginationFirstPage => 'First Page';

  @override
  String get paginationPreviousPage => 'Previous Page';

  @override
  String get paginationNextPage => 'Next Page';

  @override
  String get paginationLastPage => 'Last Page';

  @override
  String get editModeTitle => 'Edit Mode';

  @override
  String get editModeChanges => 'changes';

  @override
  String get editModeHint =>
      'Double-click to edit | Enter to confirm | Esc to cancel | Tab to switch';

  @override
  String get resultsNoDataTitle => 'No Results';

  @override
  String get resultsNoDataMessage =>
      'Results will appear after executing a query';

  @override
  String get resultsNoDataCardMessage =>
      'Card view will appear after executing a query';

  @override
  String get resultsNoDataChartMessage =>
      'Chart will appear after executing a query';

  @override
  String get resultsNoDataStatisticsMessage =>
      'Statistics will appear after executing a query';

  @override
  String get resultsNoDataExecutionPlanMessage =>
      'Click \'Execution Plan\' button to view query execution plan';

  @override
  String get statisticsTotalRows => 'Total Rows';

  @override
  String get statisticsFieldInfo => 'Field Information';

  @override
  String get statisticsNumeric => 'Numeric';

  @override
  String get statisticsText => 'Text';

  @override
  String get statisticsNumericStats => 'Numeric Statistics';

  @override
  String get statisticsCount => 'Count';

  @override
  String get statisticsSum => 'Sum';

  @override
  String get statisticsAvg => 'Average';

  @override
  String get statisticsMin => 'Minimum';

  @override
  String get statisticsMax => 'Maximum';

  @override
  String get chartXAxis => 'X Axis';

  @override
  String get chartYAxis => 'Y Axis';

  @override
  String get chartType => 'Type: ';

  @override
  String get chartCannotGenerate =>
      'Cannot generate chart: Please ensure Y-axis field contains numeric data';

  @override
  String messagesQuerySuccess(Object cols, Object rows) {
    return 'Query successful, returned $rows rows, $cols columns';
  }

  @override
  String get messagesExecuteToSeeResults =>
      'Results info will appear after executing a query';

  @override
  String sqlPreviewWillExecute(Object count, Object table) {
    return 'Will execute $count SQL statements on table `$table`:';
  }

  @override
  String get saveErrorNoTab => 'Cannot save: Current tab does not exist';

  @override
  String get saveErrorCannotExtractTable =>
      'Cannot save: Cannot extract table name from query';

  @override
  String saveErrorFailed(Object error) {
    return 'Save failed: $error';
  }

  @override
  String get exportSelectFormat => 'Select export format';

  @override
  String get toolbarExecute => 'Execute';

  @override
  String get toolbarStop => 'Stop';

  @override
  String get toolbarReadOnlyChip => 'Read-only';

  @override
  String get toolbarLimitChipTooltip =>
      'Row limit for this connection (auto LIMIT)';

  @override
  String get toolbarTimeoutChipTooltip => 'Query timeout for this connection';

  @override
  String get toolbarChipFollowSettings => 'Follow settings';

  @override
  String get toolbarChipOff => 'Off';

  @override
  String get toolbarChipFollowConnection => 'Follow connection';

  @override
  String get gridEditBlockedReadOnly =>
      'This connection is read-only — cell edits are disabled.';

  @override
  String get gridEditBlockedNoTable =>
      'Cannot infer the target table from this result — cell edits need a single-table query.';

  @override
  String gridEditsCount(Object count, Object rows) {
    return '$count cell change(s) in $rows row(s)';
  }

  @override
  String get gridCommitButton => 'Commit changes';

  @override
  String get gridDiscardButton => 'Discard';

  @override
  String gridCommitSuccess(Object rows) {
    return '$rows row(s) written back';
  }

  @override
  String gridCommitNoPrimaryKey(Object table) {
    return 'Table $table has no primary key — cannot write back.';
  }

  @override
  String gridCommitFailed(Object error) {
    return 'Write-back failed: $error';
  }

  @override
  String get statusBarReady => 'Ready';

  @override
  String get statusBarExecuting => 'Executing';

  @override
  String statusBarElapsed(String duration) {
    return 'Elapsed $duration';
  }

  @override
  String statusBarLineCol(int line, int column) {
    return 'Ln $line, Col $column';
  }

  @override
  String executionStatusBarRows(int count) {
    return '$count rows';
  }

  @override
  String get executionStatusBarErrorHint =>
      'Click a result tab to see error details';

  @override
  String get toolbarExecutionPlan => 'Execution Plan';

  @override
  String get toolbarFormat => 'Format';

  @override
  String get toolbarSave => 'Save';

  @override
  String get splitButton => 'Split Editor';

  @override
  String get horizontalSplit => 'Horizontal Split';

  @override
  String get verticalSplit => 'Vertical Split';

  @override
  String get refreshData => 'Refresh Data';

  @override
  String get analyzingDatabasePerformance =>
      'Analyzing database performance...';

  @override
  String get fullTableScanDetected => 'Full Table Scan Detected';

  @override
  String get fullTableScanDesc =>
      'Query uses full table scan (type=ALL), consider adding index on WHERE clause columns';

  @override
  String get timeThreshold => 'Time Threshold:';

  @override
  String get searchPlaceholder => 'Search...';

  @override
  String get closeBtn => 'Close';

  @override
  String get apiSettingsSavedMsg => 'API settings saved';

  @override
  String get resultsHeaderExport => 'Export';

  @override
  String get resultsHeaderSearch => 'Search';

  @override
  String get resultsHeaderClear => 'Clear';

  @override
  String get resultsHeaderSubmit => 'Submit';

  @override
  String get connectionStatusConnected => 'Connected';

  @override
  String get connectionStatusNotConnected => 'Not Connected';

  @override
  String get selectConnection => 'Select Connection...';

  @override
  String get selectDatabase => 'Select Database';

  @override
  String get aiQuickActionOptimizeSql => 'Optimize SQL';

  @override
  String get aiQuickActionExplainQuery => 'Explain Query';

  @override
  String get aiQuickActionGenerateInsert => 'Generate INSERT';

  @override
  String get aiQuickActionGenerateUpdate => 'Generate UPDATE';

  @override
  String get aiQuickActionGenerateDelete => 'Generate DELETE';

  @override
  String get aiQuickActionCreateTable => 'Create Table Statement';

  @override
  String get aiQuickActionSecurityCheck => 'Security Check';

  @override
  String get aiQuickActionIndexSuggestion => 'Index Suggestion';

  @override
  String get aiQuickActionExecutionPlan => 'Execution Plan';

  @override
  String get aiQuickActionQueryHistory => 'Query History';

  @override
  String get shortcutCategoryQuery => 'Query';

  @override
  String get queryCancelled => 'Query cancelled';

  @override
  String queryFailed(Object error) {
    return 'Query failed: $error';
  }

  @override
  String querySuccessWithTime(Object count, Object time) {
    return 'Query successful, returned $count rows (${time}ms)';
  }

  @override
  String get cancelingQuery => 'Canceling query...';

  @override
  String get cancelQueryFailed => 'Unable to cancel query';

  @override
  String get confirmCancelTransaction => 'Confirm Cancel Transaction';

  @override
  String get confirmCancelTransactionMessage =>
      'The current connection has an uncommitted transaction. Canceling the query will disconnect and reconnect, causing the transaction to rollback. Continue?';

  @override
  String get cancel => 'Cancel';

  @override
  String get explainPlanSuccess => 'Explain plan retrieved successfully';

  @override
  String explainPlanFailed(Object error) {
    return 'Unable to get explain plan: $error';
  }

  @override
  String get queryEmptyCannotSave => 'The query is empty and cannot be saved';

  @override
  String get saveQueryTitle => 'Save Query';

  @override
  String get queryName => 'Query Name';

  @override
  String get enterQueryName => 'Enter query name';

  @override
  String get saveQueryHint => 'Will be saved to saved queries list (max 20)';

  @override
  String querySaved(Object name) {
    return 'Query saved: $name';
  }

  @override
  String get saveQueryLimitReached =>
      'Save limit reached (20). Please delete some queries first.';

  @override
  String savedQueryNameExists(Object name) {
    return 'Saved query name \"$name\" already exists for this connection';
  }

  @override
  String get sqlFormatted => 'SQL formatted';

  @override
  String get pleaseEnterSqlCode => 'Please enter the SQL code';

  @override
  String get noConnectedServer => 'No connected server';

  @override
  String get split2Hint => 'Split 2 - Enter SQL query...';

  @override
  String get toolbarClose => 'Close';

  @override
  String connectedToServer(Object serverName) {
    return 'Connected to $serverName';
  }

  @override
  String openTableDataFailed(Object error) {
    return 'Unable to open table data: $error';
  }

  @override
  String queryTable(Object tableName) {
    return 'Query $tableName';
  }

  @override
  String openViewFailed(Object error) {
    return 'Unable to open view: $error';
  }

  @override
  String queryView(Object viewName) {
    return 'Query $viewName';
  }

  @override
  String openProcedureFailed(Object error) {
    return 'Unable to open stored procedure: $error';
  }

  @override
  String callProcedure(Object procName) {
    return 'Call $procName';
  }

  @override
  String get cancelConnection => 'Cancel Connection';

  @override
  String get deleteConnectionTitle => 'Delete Connection';

  @override
  String deleteConnectionConfirm(Object serverName) {
    return 'Are you sure you want to delete connection \"$serverName\"?';
  }

  @override
  String get refresh => 'Refresh';

  @override
  String get createNewTable => 'New Table';

  @override
  String get erDiagram => 'ER Diagram';

  @override
  String get properties => 'Properties';

  @override
  String get exportStructure => 'Export Structure';

  @override
  String get dropDatabase => 'Drop Database';

  @override
  String get confirmDeleteDatabase => 'Delete Database';

  @override
  String get confirmDropTable => 'Drop Table';

  @override
  String typeNameToConfirm(String name) {
    return 'Type \"$name\" to confirm';
  }

  @override
  String dropDatabaseWarning(String name) {
    return 'Database \"$name\" will be permanently deleted.';
  }

  @override
  String objectCountWarning(int count, String type) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count ${type}s will be destroyed',
      one: '1 $type will be destroyed',
    );
    return '$_temp0';
  }

  @override
  String get allDataWillBeLost => 'All data will be lost';

  @override
  String copiedDbStructureToClipboard(Object dbName) {
    return 'Copied structure of $dbName to clipboard';
  }

  @override
  String databaseDeleted(Object dbName) {
    return 'Database $dbName deleted';
  }

  @override
  String get browseData => 'Browse Data';

  @override
  String get editTable => 'Edit Table';

  @override
  String get copyTableName => 'Copy Table Name';

  @override
  String get copyColumnName => 'Copy Column Name';

  @override
  String get copyIndexName => 'Copy Index Name';

  @override
  String get dropColumn => 'Drop Column';

  @override
  String get editIndex => 'Edit Index';

  @override
  String get dropIndex => 'Drop Index';

  @override
  String confirmDropColumn(Object column, Object table) {
    return 'Are you sure you want to drop column \"$column\" from table \"$table\"?';
  }

  @override
  String confirmDropIndex(Object index) {
    return 'Are you sure you want to drop index \"$index\"?';
  }

  @override
  String columnDropped(Object column) {
    return 'Column \"$column\" dropped';
  }

  @override
  String indexDropped(Object index) {
    return 'Index \"$index\" dropped';
  }

  @override
  String dropColumnFailed(Object error) {
    return 'Failed to drop column: $error';
  }

  @override
  String dropIndexFailed(Object error) {
    return 'Failed to drop index: $error';
  }

  @override
  String get loadingSchema => 'Loading...';

  @override
  String get noColumns => 'No Columns';

  @override
  String get noIndexes => 'No indexes';

  @override
  String get noProgrammableObjects =>
      'This database type does not support programmable objects';

  @override
  String get exportData => 'Export Data';

  @override
  String get dataSync => 'Data Sync';

  @override
  String get rename => 'Rename';

  @override
  String get truncate => 'Truncate';

  @override
  String get dropTable => 'Drop Table';

  @override
  String loadTableStructureFailed(Object error) {
    return 'Unable to load table structure: $error';
  }

  @override
  String get tableNameCopied => 'Table name copied';

  @override
  String copiedTableDataToClipboard(Object tableName) {
    return 'Copied data of $tableName to clipboard';
  }

  @override
  String tableRenamedTo(Object newName) {
    return 'Table renamed to $newName';
  }

  @override
  String renameFailed(Object error) {
    return 'Rename failed: $error';
  }

  @override
  String tableTruncated(Object tableName) {
    return 'Table $tableName truncated';
  }

  @override
  String truncateFailed(Object error) {
    return 'Truncate failed: $error';
  }

  @override
  String tableDeleted(Object tableName) {
    return 'Table $tableName deleted';
  }

  @override
  String get analyzeTable => 'Analyze Table';

  @override
  String get optimizeTable => 'Optimize Table';

  @override
  String get checkTable => 'Check Table';

  @override
  String confirmAnalyzeTable(Object tableName) {
    return 'Analyze Table $tableName';
  }

  @override
  String confirmAnalyzeTableMessage(Object tableName) {
    return 'This will update index statistics for table \"$tableName\".';
  }

  @override
  String confirmOptimizeTable(Object tableName) {
    return 'Optimize Table $tableName';
  }

  @override
  String confirmOptimizeTableMessage(Object tableName) {
    return 'This will defragment and reclaim unused space for table \"$tableName\".';
  }

  @override
  String confirmCheckTable(Object tableName) {
    return 'Check Table $tableName';
  }

  @override
  String confirmCheckTableMessage(Object tableName) {
    return 'This will check table \"$tableName\" for errors.';
  }

  @override
  String get optimizeTableWarning =>
      'This operation may lock the table and take a long time on large tables.';

  @override
  String analyzeTableResultTitle(Object tableName) {
    return 'Analyze Result: $tableName';
  }

  @override
  String optimizeTableResultTitle(Object tableName) {
    return 'Optimize Result: $tableName';
  }

  @override
  String checkTableResultTitle(Object tableName) {
    return 'Check Result: $tableName';
  }

  @override
  String get maintenanceExecutedSql => 'Executed SQL';

  @override
  String get maintenanceResult => 'Result';

  @override
  String maintenanceFailed(Object operation, Object error) {
    return '$operation failed: $error';
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
  String get indexTypeNormal => 'Normal';

  @override
  String get indexTypeUnique => 'Unique';

  @override
  String get hintIndexColumns => 'e.g.: id, name';

  @override
  String get pleaseDefineAtLeastOneColumn =>
      'Please define at least one column';

  @override
  String tableCreated(Object tableName) {
    return 'Table $tableName created successfully';
  }

  @override
  String createFailed(Object error) {
    return 'Create failed: $error';
  }

  @override
  String get tableModified => 'Table modified successfully';

  @override
  String modifyFailed(Object error) {
    return 'Modify failed: $error';
  }

  @override
  String get noInformation => 'No information';

  @override
  String get truncateTableData => 'Truncate Table Data';

  @override
  String get menuCut => 'Cut';

  @override
  String get menuCopy => 'Copy';

  @override
  String get menuPaste => 'Paste';

  @override
  String get menuSelectAll => 'Select All';

  @override
  String get menuFormatSql => 'Format SQL';

  @override
  String get menuExecuteQuery => 'Execute Query';

  @override
  String get commandNewConnection => 'New Connection';

  @override
  String get commandNewTab => 'New Tab';

  @override
  String get commandExecuteQuery => 'Execute Query';

  @override
  String get commandFormatSql => 'Format SQL';

  @override
  String get commandToggleAiPanel => 'Toggle AI Panel';

  @override
  String get commandQueryHistory => 'Query History';

  @override
  String get commandShortcuts => 'Keyboard Shortcuts';

  @override
  String get commandSettings => 'Settings';

  @override
  String get commandCategoryHistory => 'History';

  @override
  String get commandCategoryHelp => 'Help';

  @override
  String get commandDescNewConnection => 'Create a new database connection';

  @override
  String get commandDescNewTab => 'Create a new query tab';

  @override
  String get commandDescExecuteQuery => 'Run current SQL query';

  @override
  String get commandDescFormatSql => 'Format SQL code';

  @override
  String get commandDescToggleSidebar => 'Show or hide sidebar';

  @override
  String get commandDescToggleAiPanel => 'Show or hide AI assistant panel';

  @override
  String get commandDescQueryHistory => 'View execution history';

  @override
  String get commandDescShortcuts => 'View all keyboard shortcuts';

  @override
  String get commandDescSettings => 'Open application settings';

  @override
  String get searchNavigateKeys => '↑↓/Mouse';

  @override
  String get menuConnect => 'Connect';

  @override
  String get menuCancelConnection => 'Cancel Connection';

  @override
  String get menuDisconnect => 'Disconnect';

  @override
  String get menuRefresh => 'Refresh';

  @override
  String get menuEditConnection => 'Edit Connection';

  @override
  String get menuCloneConnection => 'Clone Connection';

  @override
  String get menuDeleteConnection => 'Delete Connection';

  @override
  String get addColumn => 'Add Column';

  @override
  String get addIndex => 'Add Index';

  @override
  String get noIndexesClickToAdd =>
      'No indexes yet. Click the button above to add one.';

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
      'CSV is a universal spreadsheet format, compatible with Excel, Numbers, Google Sheets, etc.';

  @override
  String get formatJSONDesc =>
      'JSON is a structured data format suitable for program reading or API calls.';

  @override
  String get formatExcelDesc =>
      'Excel format preserves data types and formatting, suitable for in-depth data analysis.';

  @override
  String get formatMarkdownDesc =>
      'Markdown table format is suitable for documentation, reports, or code review.';

  @override
  String get formatSqlInsertDesc =>
      'SQL INSERT statements can be directly imported into other databases, suitable for data migration.';

  @override
  String get copiedToClipboard => 'Copied to clipboard';

  @override
  String get hintFormatName => 'e.g.: My Format';

  @override
  String get hintOptionalDescription => 'Optional description';

  @override
  String get formatterSelectPreset => 'Select preset';

  @override
  String get formatterFormat => 'Format';

  @override
  String get formatterCopyResult => 'Copy result';

  @override
  String get formatterHintInputSql => 'Enter SQL code here...';

  @override
  String get formatterSpace => 'Space';

  @override
  String get formatterTab => 'Tab';

  @override
  String get formatterIndentSize => 'Indent size';

  @override
  String get formatterMaxLineLength => 'Max line length';

  @override
  String get formatterUppercaseKeywords => 'Uppercase keywords';

  @override
  String get formatterAlignKeywords => 'Align keywords';

  @override
  String get formatterPreserveComments => 'Preserve comments';

  @override
  String get formatterNewlineBeforeParentheses => 'Newline before parentheses';

  @override
  String get formatterCompactMode => 'Compact mode';

  @override
  String get formatterPosition => 'Position';

  @override
  String get formatterEnd => 'End';

  @override
  String get formatterStart => 'Start';

  @override
  String loadFailed(Object error) {
    return 'Load failed: $error';
  }

  @override
  String exportFailed(String error) {
    return 'Export failed: $error';
  }

  @override
  String timeAgoDays(Object count) {
    return '$count days ago';
  }

  @override
  String timeAgoHours(Object count) {
    return '$count hours ago';
  }

  @override
  String timeAgoMinutes(Object count) {
    return '$count minutes ago';
  }

  @override
  String get timeAgoJustNow => 'Just now';

  @override
  String get optimizationFullTableScan => 'Full Table Scan Detected';

  @override
  String get optimizationFullTableScanDesc =>
      'Query uses full table scan (type=ALL). Consider adding index on WHERE clause columns.';

  @override
  String get optimizationFilesort => 'Filesort';

  @override
  String get optimizationFilesortDesc =>
      'Query uses filesort (Using filesort). Consider adding index on ORDER BY columns.';

  @override
  String get optimizationTemporary => 'Temporary Table';

  @override
  String get optimizationTemporaryDesc =>
      'Query uses temporary table (Using temporary). Consider optimizing GROUP BY or DISTINCT queries.';

  @override
  String get optimizationLowEfficiency => 'Low Scan Efficiency';

  @override
  String optimizationLowEfficiencyDesc(
    Object ratio,
    Object rowsExamined,
    Object rowsSent,
  ) {
    return 'Scanned $rowsExamined rows but only returned $rowsSent rows. Scan ratio: $ratio:1';
  }

  @override
  String get optimizationNoIssue => 'No obvious issues found';

  @override
  String get optimizationNoIssueDesc => 'Query execution plan looks normal';

  @override
  String get optimizationSuggestions => 'Optimization Suggestions';

  @override
  String get indexTypeDistribution => 'Index Type Distribution';

  @override
  String get noData => 'No data';

  @override
  String get indexPrimary => 'Primary';

  @override
  String get indexUnique => 'Unique';

  @override
  String get indexNormal => 'Normal';

  @override
  String get totalIndexes => 'Total Indexes';

  @override
  String get indexUsed => 'Used';

  @override
  String get indexUnused => 'Unused';

  @override
  String indexCount(Object count) {
    return '$count indexes';
  }

  @override
  String columnCardinality(Object cardinality) {
    return 'Cardinality: $cardinality';
  }

  @override
  String columnsLabel(Object columns) {
    return 'Columns: $columns';
  }

  @override
  String get totalTables => 'Total Tables';

  @override
  String get totalRows => 'Total Rows';

  @override
  String get dataSize => 'Data Size';

  @override
  String get indexSize => 'Index Size';

  @override
  String get tableSizeDistribution => 'Table Size Distribution (Top 10)';

  @override
  String get tableNameLabel => 'Table Name';

  @override
  String get tableEngineLabel => 'Engine';

  @override
  String get tableRowCountLabel => 'Rows';

  @override
  String get tableDataSizeLabel => 'Data Size';

  @override
  String get tableIndexSizeLabel => 'Index Size';

  @override
  String get tableTotalSizeLabel => 'Total Size';

  @override
  String get tableRatioLabel => 'Ratio';

  @override
  String get databasePerformanceReport => 'Database Performance Report';

  @override
  String databaseLabel(Object name) {
    return 'Database: $name';
  }

  @override
  String generatedAtLabel(Object time) {
    return 'Generated at: $time';
  }

  @override
  String get tableCountLabel => 'Tables';

  @override
  String get slowQueryCountLabel => 'Slow Queries';

  @override
  String get suggestionCountLabel => 'Suggestions';

  @override
  String impactLevel(Object level) {
    return 'Impact: $level';
  }

  @override
  String get impactHigh => 'High';

  @override
  String get impactMedium => 'Medium';

  @override
  String get impactLow => 'Low';

  @override
  String get recommendedAction => 'Recommended Action:';

  @override
  String slowQueryTopN(Object count) {
    return 'Slow Query Top $count';
  }

  @override
  String get largeTableStats => 'Large Table Statistics';

  @override
  String get tabRenameTitle => 'Rename Query';

  @override
  String get tabRenameHint => 'Enter query name';

  @override
  String get tabRename => 'Rename';

  @override
  String get tabClose => 'Close';

  @override
  String get tabCloseOthers => 'Close Others';

  @override
  String get tabCloseToRight => 'Close to Right';

  @override
  String get tabCloseAll => 'Close All';

  @override
  String get tabDuplicate => 'Duplicate Tab';

  @override
  String get tabNewTooltip => 'New Query (Ctrl+T)';

  @override
  String tabNewQueryTitle(Object count) {
    return 'Query $count';
  }

  @override
  String get confirm => 'Confirm';

  @override
  String get copySuffix => '(Copy)';

  @override
  String get triggerTitle => 'Triggers';

  @override
  String triggerFailedToLoad(Object error) {
    return 'Unable to load triggers: $error';
  }

  @override
  String get triggerFailedToLoadDefinition =>
      'Unable to load trigger definition';

  @override
  String get triggerDeleteTitle => 'Delete Trigger';

  @override
  String triggerDeleteConfirm(Object name) {
    return 'Are you sure you want to delete trigger \"$name\"?';
  }

  @override
  String triggerDeleted(Object name) {
    return 'Trigger \"$name\" deleted';
  }

  @override
  String triggerDeleteFailed(Object error) {
    return 'Unable to delete trigger: $error';
  }

  @override
  String get triggerCannotDisable =>
      'MySQL triggers cannot be disabled directly. Use Drop to remove.';

  @override
  String get triggerShowList => 'Show List';

  @override
  String get triggerGroupByTable => 'Group by Table';

  @override
  String get triggerSearchHint => 'Search triggers...';

  @override
  String get triggerNoTriggers => 'No triggers found';

  @override
  String get triggerCreate => 'Create Trigger';

  @override
  String get triggerViewDefinition => 'View Definition';

  @override
  String get triggerCopyName => 'Copy Name';

  @override
  String triggerCopied(Object name) {
    return 'Copied \"$name\" to clipboard';
  }

  @override
  String get triggerNew => 'New Trigger';

  @override
  String triggerDefinition(Object name) {
    return 'Trigger: $name';
  }

  @override
  String get formatterSqlFormat => 'SQL Format';

  @override
  String get formatterSavePreset => 'Save Preset';

  @override
  String get formatterPresetName => 'Preset Name';

  @override
  String get formatterCustomPreset => 'Custom Preset';

  @override
  String get formatterBuiltIn => 'Built-in';

  @override
  String get formatterSaveAsPreset => 'Save current settings as preset';

  @override
  String get formatterDeletePreset => 'Delete Preset';

  @override
  String get formatterInput => 'Input';

  @override
  String get formatterOptions => 'Formatting Options';

  @override
  String get formatterIndent => 'Indent';

  @override
  String get formatterKeywords => 'Keywords';

  @override
  String get formatterCommaStyle => 'Comma Style';

  @override
  String get formatterApplyToEditor => 'Apply to Editor';

  @override
  String filterTitle(String columnName) {
    return 'Filter: $columnName';
  }

  @override
  String get filterEquals => 'equals';

  @override
  String get filterNotEquals => 'not equals';

  @override
  String get filterContains => 'contains';

  @override
  String get filterNotContains => 'not contains';

  @override
  String get filterGreaterThan => 'greater than';

  @override
  String get filterLessThan => 'less than';

  @override
  String get filterIsEmpty => 'is empty';

  @override
  String get filterIsNotEmpty => 'is not empty';

  @override
  String get filterRegex => 'regex';

  @override
  String get filterValue => 'Value';

  @override
  String get filterEnterValue => 'Enter filter value';

  @override
  String get filterCaseSensitive => 'Case sensitive';

  @override
  String get filterTimeFilter => 'Time Filter';

  @override
  String get filterToday => 'Today';

  @override
  String get filterLast24Hours => 'Last 24 Hours';

  @override
  String get filterLast7Days => 'Last 7 Days';

  @override
  String get filterLast30Days => 'Last 30 Days';

  @override
  String rowCountLabel(Object count) {
    return '$count rows';
  }

  @override
  String get toolbarCodeSnippets => 'Code Snippets (Ctrl+Shift+S)';

  @override
  String get toolbarCloseSplit => 'Close Split';

  @override
  String get editorHintText =>
      'Enter SQL query... (Ctrl+Space for autocomplete, F5/Ctrl+Enter to execute)';

  @override
  String get editorHintTextMongodb =>
      'Enter MongoDB query... (F5/Ctrl+Enter to execute)';

  @override
  String get editorHintTextRedis =>
      'Enter Redis command... (F5/Ctrl+Enter to execute)';

  @override
  String allStatementsSuccess(int count, int time) {
    return 'All $count statements executed successfully (${time}ms)';
  }

  @override
  String statementsPartialSuccess(
    int success,
    int total,
    int failed,
    int time,
  ) {
    return '$success/$total statements succeeded, $failed failed (${time}ms)';
  }

  @override
  String statementsAllSuccess(int count) {
    return '$count statements executed successfully';
  }

  @override
  String statementsPartialSuccessShort(int success, int total, int failed) {
    return '$success/$total succeeded, $failed failed';
  }

  @override
  String get aiPanelCustomModel => 'Custom Model';

  @override
  String get aiPanelBookmarks => 'Bookmarks';

  @override
  String get aiPanelScrollToMessageDeveloping =>
      'Scroll to message feature is under development';

  @override
  String get aiPanelBranchConversationCreated => 'Branch conversation created';

  @override
  String get aiPanelNoConnections =>
      'No connections yet. Create one to get started.';

  @override
  String get aiPanelConversationList => 'Conversation List';

  @override
  String get aiPanelSelectConnection => 'Select Connection';

  @override
  String get aiPanelNoConnection => 'No Connection';

  @override
  String get aiPanelSelectDatabaseFirst => 'Please select a connection first';

  @override
  String get aiPanelSelectDatabase => 'Select Database';

  @override
  String get aiPanelAllDatabases => 'All Databases';

  @override
  String get aiPanelConnectionFailed => 'Connection failed';

  @override
  String get aiPanelUnknownError => 'Unknown error';

  @override
  String get aiPanelLoadDatabasesFailed => 'Unable to load databases';

  @override
  String get aiPanelDangerousOperation => 'Dangerous Operation';

  @override
  String get aiPanelOptimizeSql => 'Optimize SQL';

  @override
  String get aiPanelSecurityAnalysis => 'Security Analysis';

  @override
  String get aiPanelExecutionPlan => 'Execution Plan';

  @override
  String get aiPanelIndexSuggestions => 'Index Suggestions';

  @override
  String get aiPanelInputHint =>
      'Ask a question about your database, e.g., \"How can I optimize this query?\"';

  @override
  String get aiPanelStop => 'Stop';

  @override
  String get aiPanelSend => 'Send';

  @override
  String get aiPanelSelectConnectionFirst =>
      'Please select a connection from the dropdown above first.';

  @override
  String aiPanelConnectionNotAvailable(Object name) {
    return 'Connection \"$name\" is not connected or unavailable. Please connect to it first.';
  }

  @override
  String get aiPanelTable => 'Table';

  @override
  String get aiPanelDangerousOperationBadge => 'Dangerous Operation';

  @override
  String get aiPanelThinkingProcess => 'Thinking Process';

  @override
  String get aiPanelExpandThinking => 'Expand thinking process';

  @override
  String get aiPanelCollapseThinking => 'Collapse thinking process';

  @override
  String get aiPanelRenameSession => 'Rename Session';

  @override
  String get aiPanelSessionTitle => 'Session Title';

  @override
  String get aiPanelDeleteSession => 'Delete Session';

  @override
  String aiPanelDeleteSessionConfirm(Object name) {
    return 'Are you sure you want to delete \"$name\"?';
  }

  @override
  String get aiPanelRename => 'Rename';

  @override
  String get aiPanelUnarchive => 'Unarchive';

  @override
  String get aiPanelArchive => 'Archive';

  @override
  String get aiPanelSessions => 'Sessions';

  @override
  String get aiPanelSearchSessions => 'Search sessions';

  @override
  String get aiPanelNoSessions => 'No sessions';

  @override
  String aiPanelArchivedSessions(Object count) {
    return 'Archived Sessions ($count)';
  }

  @override
  String get aiPanelJustNow => 'Just now';

  @override
  String aiPanelMinutesAgo(Object count) {
    return '$count minutes ago';
  }

  @override
  String aiPanelHoursAgo(Object count) {
    return '$count hours ago';
  }

  @override
  String aiPanelDaysAgo(Object count) {
    return '$count days ago';
  }

  @override
  String get aiPanelSelectProvider => 'Select Provider';

  @override
  String aiPanelSelectModelCurrent(Object provider) {
    return 'Select Model (Current: $provider)';
  }

  @override
  String aiPanelApiConfigCurrent(Object provider) {
    return 'API Configuration (Current: $provider)';
  }

  @override
  String get aiPanelModelProviderMismatch =>
      'The selected model is not compatible with the current provider';

  @override
  String get aiPanelAllowSession => 'Allow this session';

  @override
  String get aiPanelNoBookmarks => 'No bookmarks';

  @override
  String get aiPanelClickBookmarkIcon =>
      'Click the bookmark icon on a message to add a bookmark';

  @override
  String get aiCmdOptimizeSql => 'Optimize SQL statement';

  @override
  String get aiCmdExplainQuery => 'Explain query plan';

  @override
  String get aiCmdGenerateCrud => 'Generate CRUD statements';

  @override
  String get aiCmdAnalyzeTable => 'Analyze table structure';

  @override
  String get aiCmdShowHistory => 'View query history';

  @override
  String get aiCmdShowBookmarks => 'View bookmarks';

  @override
  String get aiCmdBranchConversation => 'Create branch conversation';

  @override
  String get aiCmdListDatabases => 'List all databases';

  @override
  String get aiCmdListTables => 'List all tables';

  @override
  String get settingsThemeMode => 'Theme Mode';

  @override
  String get settingsThemeColor => 'Accent Color';

  @override
  String get settingsSystem => 'System';

  @override
  String get settingsPreview => 'Preview';

  @override
  String get settingsPrimaryButton => 'Primary Button';

  @override
  String get settingsSecondaryButton => 'Secondary Button';

  @override
  String get settingsApply => 'Apply';

  @override
  String get colorBlue => 'Blue';

  @override
  String get colorPurple => 'Purple';

  @override
  String get colorGreen => 'Green';

  @override
  String get colorOrange => 'Orange';

  @override
  String get colorRed => 'Red';

  @override
  String get colorCyan => 'Cyan';

  @override
  String get colorPink => 'Pink';

  @override
  String get colorYellow => 'Yellow';

  @override
  String get aiChatPageTitle => 'AI Assistant';

  @override
  String get messageLabelYou => 'You';

  @override
  String get messageLabelAi => 'AI';

  @override
  String get messageStatusSending => 'Sending';

  @override
  String get messageStatusGenerating => 'Generating';

  @override
  String get messageStatusFailed => 'Failed';

  @override
  String get messageStatusCancelled => 'Cancelled';

  @override
  String get messageStatusError => 'Error';

  @override
  String get messageStatusThinking => 'Thinking';

  @override
  String tokenUsagePrompt(int count) {
    return 'Input $count';
  }

  @override
  String tokenUsageCompletion(int count) {
    return 'Output $count';
  }

  @override
  String tokenUsageTotal(int count) {
    return 'Total $count';
  }

  @override
  String sessionTokenUsage(
    int promptTokens,
    int completionTokens,
    int totalTokens,
  ) {
    return 'Session: Input $promptTokens · Output $completionTokens · Total $totalTokens';
  }

  @override
  String get messageActionRegenerate => 'Regenerate';

  @override
  String get tooltipCopyCode => 'Copy code';

  @override
  String get tooltipExecuteCode => 'Execute code';

  @override
  String get messageCopied => 'Copied';

  @override
  String toolCallTitle(String name) {
    return 'Tool: $name';
  }

  @override
  String toolResultTitle(String name) {
    return 'Result: $name';
  }

  @override
  String get toolCallCompleted => 'Called and completed';

  @override
  String get toolParamLabel => 'Parameters';

  @override
  String get toolResultLabel => 'Result';

  @override
  String get toolGroupTitle => 'Tool Group';

  @override
  String toolGroupSummary(int count) {
    return 'Executed $count tools';
  }

  @override
  String toolGroupItemTitle(int index, String name) {
    return 'Tool $index: $name';
  }

  @override
  String get toolNoParams => 'No parameters';

  @override
  String get aiWelcomeTitle => 'AI Database Assistant';

  @override
  String get aiWelcomeDescription =>
      'I can help you write SQL, optimize queries, analyze table structures, check security issues, or answer any database-related questions.';

  @override
  String aiConnectedTo(String name) {
    return 'Connected: $name';
  }

  @override
  String get aiExampleSectionTitle => 'Try asking me';

  @override
  String get aiQuickActionsSectionTitle => 'Quick Actions';

  @override
  String get aiTipQuickSend => 'Ctrl + Enter to send';

  @override
  String get aiTipSlashCommands => 'Type / to see all commands';

  @override
  String get aiExampleQuestion1 => 'Optimize the performance of this query';

  @override
  String get aiExampleQuestion2 => 'Analyze the current table structure';

  @override
  String get aiExampleQuestion3 => 'Check the security of this SQL';

  @override
  String get errorApiKeyRequired => 'Please enter an API Key first';

  @override
  String get errorBaseUrlRequired => 'Please enter a Base URL first';

  @override
  String errorFetchModelsFailed(String error) {
    return 'Unable to fetch model list: $error';
  }

  @override
  String get tooltipRefreshModels => 'Refresh model list';

  @override
  String get labelCustomModelInput => 'Enter model name manually';

  @override
  String get tooltipAddModel => 'Add model';

  @override
  String get hintFetchOrInputModel =>
      'Click refresh to fetch or enter model name manually';

  @override
  String get hintFetchModels => 'Click refresh to fetch model list';

  @override
  String get errorSelectModelRequired => 'Please select or enter a model';

  @override
  String errorSaveFailed(String error) {
    return 'Save failed: $error';
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
    return 'Unable to save connection: $error';
  }

  @override
  String connDeleteConnectionFailed(String error) {
    return 'Unable to delete connection: $error';
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
    return 'Diagram saved to $path';
  }

  @override
  String get erDiagramExportNoCanvas =>
      'No diagram to export. Load a schema first.';

  @override
  String get erDiagramExportEncodeFailed =>
      'Failed to encode PNG. Please try again.';

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
    return 'Unable to pick image: $error';
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
  String get smartImportTitle => 'AI Smart Import';

  @override
  String get smartImportSubtitle =>
      'Automatically analyze file structure and import to database';

  @override
  String get smartImportClose => 'Close';

  @override
  String get smartImportTarget => 'Import Target';

  @override
  String smartImportSelectedTable(String table) {
    return 'Selected table: $table';
  }

  @override
  String get smartImportAutoInfer => 'No table selected, AI will auto-infer';

  @override
  String get smartImportLoadTables => 'Loading table list...';

  @override
  String get smartImportTableHint =>
      'Search or enter table name (leave empty for AI inference)';

  @override
  String get smartImportStepSelectFile => 'Select File';

  @override
  String get smartImportStepAnalyze => 'Analyze';

  @override
  String get smartImportStepImport => 'Import';

  @override
  String get smartImportStepComplete => 'Complete';

  @override
  String get smartImportSelectFileTitle => 'Select file to import';

  @override
  String get smartImportSelectFileHint => 'Click to select CSV or JSON file';

  @override
  String get smartImportReselectFile => 'Click to reselect';

  @override
  String get smartImportSupportedFormats =>
      'Supported formats: CSV, TSV, JSON, JSON Lines';

  @override
  String get smartImportAnalyzing => 'Analyzing file structure...';

  @override
  String get smartImportTableNotFound => 'Target table does not exist';

  @override
  String smartImportTableNotFoundMessage(String table) {
    return 'Table \"$table\" does not exist in the current database.';
  }

  @override
  String get smartImportCreateTableHint =>
      'Please execute the following CREATE TABLE statement in the SQL editor first, then reopen Smart Import.';

  @override
  String get smartImportSuggestedSQL => 'Suggested CREATE TABLE statement';

  @override
  String get smartImportCopySQL => 'Copy SQL';

  @override
  String get smartImportSQLCopied => 'SQL copied to clipboard';

  @override
  String get smartImportImporting => 'Importing data...';

  @override
  String get smartImportImported => 'Imported';

  @override
  String get smartImportTotalRecords => 'Total';

  @override
  String get smartImportFailedRecords => 'Failed';

  @override
  String get smartImportProgress => 'Progress';

  @override
  String get smartImportImportComplete => 'Import Complete';

  @override
  String get smartImportTargetTable => 'Target Table';

  @override
  String get smartImportSuccessRows => 'Successfully imported';

  @override
  String get smartImportFailedRows => 'Failed to import';

  @override
  String get smartImportTotalRows => 'Total rows in table';

  @override
  String get smartImportImportFailed => 'Import Failed';

  @override
  String get smartImportFilePreview => 'File Preview';

  @override
  String get smartImportSampleData => 'Sample data (first 3 rows)';

  @override
  String get smartImportLogs => 'Import Logs';

  @override
  String get smartImportClearLogs => 'Clear';

  @override
  String get smartImportReimport => 'Re-import';

  @override
  String get smartImportStartAnalysis => 'Start Analysis';

  @override
  String get smartImportStartImport => 'Start Import';

  @override
  String get smartImportCancelImport => 'Cancel Import';

  @override
  String get smartImportUserCancelled => 'User cancelled import';

  @override
  String smartImportFileSelected(String name) {
    return 'File selected: $name';
  }

  @override
  String smartImportAnalysisComplete(
    String format,
    String encoding,
    String fields,
  ) {
    return 'Analysis complete. Format: $format, Encoding: $encoding, Fields: $fields';
  }

  @override
  String smartImportEstimatedRows(String rows) {
    return 'Estimated total rows: ~$rows';
  }

  @override
  String smartImportUsingSelectedTable(String table) {
    return 'Using selected table: $table';
  }

  @override
  String get smartImportCheckTableExists =>
      'Checking if target table exists...';

  @override
  String smartImportTableExists(String table, String count) {
    return 'Table \"$table\" exists with $count rows';
  }

  @override
  String smartImportTableNotExists(String table) {
    return 'Table \"$table\" does not exist. Please create table first.';
  }

  @override
  String get smartImportAiInferringTable => 'AI inferring table name...';

  @override
  String smartImportAiSuggestedTable(String name) {
    return 'AI suggested table name: $name';
  }

  @override
  String get smartImportDoNotImport => 'Do not import';

  @override
  String smartImportTaskDescription(int count, String table) {
    return 'Import $count to $table';
  }

  @override
  String smartImportStartImporting(String table) {
    return 'Starting data import to table \"$table\"...';
  }

  @override
  String smartImportImportResult(String imported, String failed) {
    return 'Import complete! Success: $imported rows, Failed: $failed rows';
  }

  @override
  String get smartImportQueryRowCount => 'Querying total row count...';

  @override
  String smartImportTableTotalRows(String table, String count) {
    return 'Table \"$table\" now has $count rows';
  }

  @override
  String smartImportQueryCountFailed(String error) {
    return 'Failed to query row count: $error';
  }

  @override
  String smartImportImportError(String error) {
    return 'Import failed: $error';
  }

  @override
  String get smartImportCopySuccess => 'SQL copied to clipboard';

  @override
  String smartImportRows(String count) {
    return '$count rows';
  }

  @override
  String get smartImportAiModel => 'AI Model';

  @override
  String get aiPanelFullscreen => 'Fullscreen';

  @override
  String get aiPanelExitFullscreen => 'Exit Fullscreen';

  @override
  String get aiPanelOpenInNewQuery => 'Opened in new query';

  @override
  String aiPanelInsertStatementsGenerated(int count, String tableName) {
    return 'AI has generated $count INSERT statements, ready to insert into table [$tableName].';
  }

  @override
  String get aiPanelSqlPreviewTitle => 'SQL Preview (first 3):';

  @override
  String aiPanelMoreStatements(int count) {
    return '... and $count more statements';
  }

  @override
  String aiAgentToolCallLimitReached(int count) {
    return 'AI assistant has reached the tool call limit ($count times). Please simplify your question or proceed step by step.';
  }

  @override
  String get aiAgentMaxIterationsReached =>
      'Agent reached maximum iterations and could not complete the conversation.';

  @override
  String get aiAgentDuplicateQuery =>
      'This query has already been executed. Please answer directly based on the existing results without repeating the query.';

  @override
  String aiAgentToolExecutionFailed(String error) {
    return 'Tool execution failed: $error';
  }

  @override
  String aiAgentUnknownTool(String name) {
    return 'Unknown tool: $name';
  }

  @override
  String aiContextCurrentDatabase(String name) {
    return 'Current database: $name';
  }

  @override
  String aiContextCurrentTable(String name) {
    return 'Current table: $name';
  }

  @override
  String aiContextRecentQueries(String queries) {
    return 'Recent queries: $queries';
  }

  @override
  String aiContextGoalSummary(String summary) {
    return 'Current session goal summary: $summary';
  }

  @override
  String get taskPanelTitle => 'Tasks';

  @override
  String get taskPanelEmpty => 'No tasks';

  @override
  String get taskPanelEmptyDesc =>
      'Import or export operations will appear here';

  @override
  String get taskPanelClearCompleted => 'Clear completed';

  @override
  String get taskPanelStatusPending => 'Pending';

  @override
  String get taskPanelStatusRunning => 'Running';

  @override
  String get taskPanelStatusPaused => 'Paused';

  @override
  String get taskPanelStatusCompleted => 'Completed';

  @override
  String get taskPanelStatusFailed => 'Failed';

  @override
  String get taskPanelStatusCancelled => 'Cancelled';

  @override
  String get taskTypeImport => 'Import';

  @override
  String get taskTypeExport => 'Export';

  @override
  String get taskTypeQuery => 'Query';

  @override
  String get taskActionCancel => 'Cancel';

  @override
  String get taskActionRetry => 'Retry';

  @override
  String get taskActionRemove => 'Delete';

  @override
  String get taskActionOpenFolder => 'Open folder';

  @override
  String get taskCreateExportTitle => 'Create Export Task';

  @override
  String get taskCreateExportFormat => 'Export format';

  @override
  String get taskCreateExportPath => 'Output path';

  @override
  String get taskCreateExportPathPlaceholder =>
      'Click the button on the right to select save location';

  @override
  String get taskCreateExportPathSelect => 'Select save location';

  @override
  String get taskCreateExportStart => 'Create task';

  @override
  String get taskValidationPathRequired => 'Please select an output path';

  @override
  String get taskValidationPathNotWritable =>
      'Directory is not writable, please choose another location';

  @override
  String get taskValidationPathExists =>
      'File already exists and will be overwritten';

  @override
  String taskStatusBarTasks(int count) {
    return '$count tasks';
  }

  @override
  String taskStatusBarRunning(int count) {
    return '$count running';
  }

  @override
  String get taskLogInfo => 'Info';

  @override
  String get taskLogWarning => 'Warning';

  @override
  String get taskLogError => 'Error';

  @override
  String get taskLogSuccess => 'Success';

  @override
  String get taskDetailTitle => 'Task Details';

  @override
  String get taskDetailBasicInfo => 'Basic Information';

  @override
  String get taskDetailStatistics => 'Statistics';

  @override
  String get taskDetailError => 'Error Message';

  @override
  String get taskDetailOutputFile => 'Output File';

  @override
  String get taskDetailLogs => 'Execution Logs';

  @override
  String get taskDetailCopied => 'Path copied to clipboard';

  @override
  String get taskPhaseAnalyzing => 'Analyzing...';

  @override
  String get taskPhaseQuerying => 'Querying data...';

  @override
  String get taskPhaseFormatting => 'Formatting data...';

  @override
  String get taskPhaseWriting => 'Writing file...';

  @override
  String get taskPhaseCompleted => 'Completed';

  @override
  String get aiExportButtonCreate => 'Create Export Task';

  @override
  String get aiExportButtonAnalyzing => 'Analyzing...';

  @override
  String get aiMessageExportAction => 'Export this data';

  @override
  String get smartImportCreateTask => 'Create import task in background';

  @override
  String get schemaDiffTitle => 'Schema Diff & Sync';

  @override
  String get schemaDiffMenuItem => 'Schema Diff & Sync';

  @override
  String get schemaDiffSource => 'Source';

  @override
  String get schemaDiffTarget => 'Target';

  @override
  String get schemaDiffCompareButton => 'Compare';

  @override
  String get schemaDiffSelectDatabases =>
      'Select source and target databases to compare';

  @override
  String get schemaDiffTabOverview => 'Overview';

  @override
  String get schemaDiffTabDetails => 'Details';

  @override
  String get schemaDiffTabSync => 'Sync';

  @override
  String get sidebarColumns => 'Columns';

  @override
  String get sidebarIndexes => 'Indexes';

  @override
  String get sidebarInsertIntoEditor => 'Insert into editor';

  @override
  String get sidebarForeignKeys => 'Foreign Keys';

  @override
  String get sidebarCopyIndexName => 'Copy index name';

  @override
  String get sidebarCopyForeignKeyName => 'Copy foreign key name';

  @override
  String get sidebarCopyName => 'Copy Name';

  @override
  String get sidebarReadOnlyConnection => 'Read-only connection';

  @override
  String get sidebarCopyColumnName => 'Copy column name';

  @override
  String get sidebarCopyColumnType => 'Copy column type';

  @override
  String get sidebarCopyAllColumnNames => 'Copy all column names';

  @override
  String get sidebarOpenEditorFirst => 'Open a query tab first';

  @override
  String get sidebarEvents => 'Events';

  @override
  String get sidebarProgrammableObjects => 'Programmable Objects';

  @override
  String get selectDatabaseHint =>
      'Double-click a database to view its objects';

  @override
  String get workspaceEmptyTitle => 'No Open Queries';

  @override
  String get workspaceEmptyHint => 'Create a new query tab to get started';

  @override
  String get noSearchResults => 'No matching results';

  @override
  String get page => 'Page';

  @override
  String get settingsSubscriptionSettings => 'Subscription';

  @override
  String get settingsFreePlan => 'Free';

  @override
  String get settingsFreePlanDesc => 'You are currently on the Free plan';

  @override
  String get settingsProActivated => 'Pro Activated';

  @override
  String get settingsProActivatedDesc => 'All Pro features are unlocked';

  @override
  String get settingsUpgradeToPro => 'Upgrade to Pro';

  @override
  String get settingsRestorePurchases => 'Restore Purchases';

  @override
  String get purchaseDialogTitle => 'Upgrade to Pro';

  @override
  String get purchaseDialogDesc =>
      'Unlock all premium features with a Pro subscription';

  @override
  String get purchaseDialogNoProducts => 'No products available';

  @override
  String freeAiQuotaExceeded(int count) {
    return 'You have used all $count free AI messages this month. Upgrade to Pro for unlimited AI usage.';
  }

  @override
  String freeConnectionLimitReached(int count) {
    return 'Free plan supports up to $count saved connections. Upgrade to Pro for unlimited connections.';
  }

  @override
  String freeTabLimitReached(int count) {
    return 'Free plan supports up to $count open query tabs. Upgrade to Pro for unlimited tabs.';
  }

  @override
  String get schemaDiffSyncProFeature =>
      'Schema Diff sync is a Pro feature. Start a free trial or upgrade to Pro to execute synchronization.';

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
  String get recentTables => 'Recent';

  @override
  String get dataSyncTitle => 'Data Sync';

  @override
  String get dataSyncCancel => 'Cancel';

  @override
  String get dataSyncClose => 'Close';

  @override
  String get dataSyncRestart => 'Resync';

  @override
  String get dataSyncStart => 'Start Sync';

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
  String get dataSyncStatusFailed => 'Sync Failed';

  @override
  String get dataSyncStatusCanceled => 'Canceled';

  @override
  String get dataSyncRefresh => 'Refresh';

  @override
  String get dataSyncNotConnected => 'Not connected to a DbMaster server.';

  @override
  String get dataSyncSourceConfig => 'Source';

  @override
  String get dataSyncSourceConnection => 'Source Connection';

  @override
  String get dataSyncSourceDatabase => 'Source Database';

  @override
  String get dataSyncSourceTable => 'Source Table';

  @override
  String get dataSyncTargetConfig => 'Target';

  @override
  String get dataSyncTargetConnection => 'Target Connection';

  @override
  String get dataSyncTargetDatabase => 'Target Database';

  @override
  String get dataSyncTargetTable => 'Target Table';

  @override
  String get dataSyncSegmentConfig => 'Segment';

  @override
  String get dataSyncSegmentStrategy => 'Strategy';

  @override
  String get dataSyncSegmentTypeNumeric => 'Numeric';

  @override
  String get dataSyncSegmentTypeTime => 'Time';

  @override
  String get dataSyncSegmentField => 'Field';

  @override
  String get dataSyncTimeUnit => 'Unit';

  @override
  String get dataSyncTimeUnitMinute => 'Minute';

  @override
  String get dataSyncTimeUnitHour => 'Hour';

  @override
  String get dataSyncTimeUnitDay => 'Day';

  @override
  String get dataSyncIntervalValue => 'Interval';

  @override
  String get dataSyncSegmentSize => 'Segment Size';

  @override
  String get dataSyncAdvancedOptions => 'Advanced';

  @override
  String get dataSyncPageSize => 'Page Size';

  @override
  String get dataSyncTargetStrategy => 'Target Strategy';

  @override
  String get dataSyncStrategyTruncate => 'Truncate then sync';

  @override
  String get dataSyncStrategyAppend => 'Append (ignore conflicts)';

  @override
  String get dataSyncStrategyReplace => 'Replace';

  @override
  String get dataSyncStrategyUpsert => 'Upsert';

  @override
  String get dataSyncServerTimeOnlyHint =>
      'Server background mode batches by time window only. Numeric segmentation is available in local mode.';

  @override
  String get dataSyncReplaceDowngradeWarning =>
      'Server background mode has no REPLACE INTO — submitting downgrades to \'truncate then sync\': the target table is emptied first, then fully rewritten from the source.';

  @override
  String get dataSyncCancelling =>
      'Cancelling — waiting for the current batch to finish…';

  @override
  String get dataSyncSegmentIntervalMs => 'Segment Interval (ms)';

  @override
  String get dataSyncPageIntervalMs => 'Page Interval (ms)';

  @override
  String get dataSyncPleaseCompleteConfig => 'Please complete all fields';

  @override
  String get dataSyncConnectionNotFound => 'Connection not found';

  @override
  String dataSyncFailed(String error) {
    return 'Sync failed: $error';
  }

  @override
  String get dataSyncCancelledByUser => 'Cancelled by user';

  @override
  String get dataSyncCompleted => 'Sync completed';

  @override
  String get dataSyncStatusSuccess => 'Sync Successful';

  @override
  String get dataSyncStatusCancelled => 'Sync Cancelled';

  @override
  String get dataSyncResultSourceTable => 'Source';

  @override
  String get dataSyncResultTargetTable => 'Target';

  @override
  String get dataSyncResultSyncedRows => 'Synced Rows';

  @override
  String get dataSyncResultFailedRows => 'Failed Rows';

  @override
  String get dataSyncResultDuration => 'Duration';

  @override
  String dataSyncPleaseSelect(String label) {
    return 'Please select $label';
  }

  @override
  String get dataSyncProgressDetectingSchema => 'Detecting table schema...';

  @override
  String get dataSyncProgressCountingRows => 'Counting total rows...';

  @override
  String get dataSyncProgressCalculatingSegments => 'Calculating segments...';

  @override
  String get dataSyncProgressEmptyTable =>
      'Source table is empty, sync completed';

  @override
  String get dataSyncProgressTruncatingTarget => 'Truncating target table...';

  @override
  String get dataSyncProgressCancelled => 'Sync cancelled';

  @override
  String dataSyncProgressSyncingSegment(int current, int total) {
    return 'Syncing segment $current/$total...';
  }

  @override
  String dataSyncProgressPageStatus(
    int current,
    int total,
    int synced,
    int totalRows,
  ) {
    return 'Segment $current/$total, synced $synced / $totalRows rows';
  }

  @override
  String dataSyncProgressCompleted(int synced, int failed, int skipped) {
    return 'Sync completed! Success: $synced rows, Failed: $failed rows, Skipped: $skipped rows';
  }

  @override
  String dataSyncErrorDateTimeParse(String field, String min, String max) {
    return 'Field `$field` cannot be parsed as datetime: min=$min, max=$max';
  }

  @override
  String dataSyncErrorNumericParse(String field, String min, String max) {
    return 'Field `$field` cannot be parsed as number: min=$min, max=$max';
  }

  @override
  String get statsToggle => 'Stats';

  @override
  String get statsChooseColumns => 'Choose columns';

  @override
  String get statsApproximateTooltip =>
      'Values prefixed with ~ are approximate';

  @override
  String statsApproximateValue(String value) {
    return 'Approximate (~$value)';
  }

  @override
  String get statsExactValue => 'Exact';

  @override
  String get statsForeignKeys => 'Foreign Keys';

  @override
  String get statsNoForeignKeys => 'No foreign keys';

  @override
  String dataSyncProgressSynced(int count) {
    return 'Synced $count rows';
  }

  @override
  String dataSyncProgressTotal(int count) {
    return '$count rows';
  }

  @override
  String dataSyncProgressFailed(int count) {
    return 'Failed $count rows';
  }

  @override
  String get unsavedChangesTitle => 'Unsaved Changes';

  @override
  String get unsavedChangesMessage =>
      'This tab has unsaved changes. Close without saving?';

  @override
  String get discardChanges => 'Discard';

  @override
  String tabCloseConfirmMessage(String title) {
    return 'Do you want to save the changes made to \"$title\" before closing?';
  }

  @override
  String get bulkCloseDialogTitle => 'Unsaved Changes';

  @override
  String get bulkCloseDialogMessage =>
      'The following tabs have unsaved changes:';

  @override
  String get bulkCloseSaveAll => 'Save All';

  @override
  String get bulkCloseDiscardAll => 'Discard All';

  @override
  String get bulkCloseReviewTitle => 'Review Tabs';

  @override
  String get bulkCloseDecisionSave => 'Save';

  @override
  String get bulkCloseDecisionDiscard => 'Discard';

  @override
  String get bulkCloseDecisionPending => 'Keep Open';

  @override
  String bulkCloseSaveFailed(Object title) {
    return 'Failed to save $title.';
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
  String get exportConnectionsTitle => 'Export All Connections';

  @override
  String get importConnectionsTitle => 'Import Connections';

  @override
  String get exportConnectionsCount => 'Connections to export';

  @override
  String get exportPasswordHint => 'Backup password';

  @override
  String get confirmExportPasswordHint => 'Confirm backup password';

  @override
  String get passwordsDoNotMatch => 'Passwords do not match';

  @override
  String get importPasswordHint => 'Backup password';

  @override
  String get selectExportFile => 'Save to file';

  @override
  String get selectImportFile => 'Select backup file';

  @override
  String selectImportFileFailed(String error) {
    return 'Failed to pick file: $error';
  }

  @override
  String get conflictStrategyLabel => 'If connection name already exists';

  @override
  String get conflictStrategySkip => 'Skip';

  @override
  String get conflictStrategyRename => 'Rename';

  @override
  String get conflictStrategyOverwrite => 'Overwrite';

  @override
  String get exportSuccess => 'Connections exported successfully';

  @override
  String get importSuccess => 'Connections imported successfully';

  @override
  String get invalidPassword => 'Invalid password';

  @override
  String get invalidFile => 'Invalid or corrupted backup file';

  @override
  String get noConnectionsToExport => 'No connections to export';

  @override
  String get exportThisConnection => 'Export This Connection';

  @override
  String get commandCategoryTools => 'Tools';

  @override
  String get passwordRequiredTitle => 'Password Required';

  @override
  String passwordRequiredMessage(String serverName) {
    return 'Enter the password for $serverName to connect';
  }

  @override
  String get connectionConnectNoPassword => 'Connect Without Password';

  @override
  String get embeddedRequiresRemoteServer => 'Remote server only';

  @override
  String get serverSessionExpiredTitle => 'Session Expired';

  @override
  String get serverSessionExpiredMessage =>
      'Your server session has expired or was revoked. Please sign in again to continue.';

  @override
  String get serverSessionRelogin => 'Sign in again';

  @override
  String get serverReconnectLastSession => 'Reconnect to last server';

  @override
  String get serverReconnectFailed =>
      'The stored session is no longer valid. Please sign in again.';

  @override
  String sidebarEmptyTableFailed(String error) {
    return 'Failed to empty table: $error';
  }

  @override
  String sidebarDropViewFailed(String error) {
    return 'Failed to drop view: $error';
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
    return 'Database saved to $path';
  }

  @override
  String sidebarSaveAsFailed(String error) {
    return 'Failed to save database: $error';
  }

  @override
  String sidebarSaveAsExists(String path) {
    return 'File already exists: $path';
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
    return 'Are you sure you want to drop view \"$viewName\"?\n\nThis action cannot be undone.';
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
  String get sidebarBrowseData => 'Browse Data';

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
  String get connectionMongoMode => 'Connection Mode';

  @override
  String get connectionMongoModeDirect => 'Direct (Single Host)';

  @override
  String get connectionMongoModeReplicaSet => 'Replica Set';

  @override
  String get connectionMongoSeedHosts => 'Seed Hosts';

  @override
  String get connectionMongoSeedHostsHint =>
      'List all replica-set members (host:port, one per line). The driver auto-discovers the primary; this list is the source of truth.';

  @override
  String get connectionMongoSeedHostsRequired =>
      'At least one seed host (host:port) is required';

  @override
  String get connectionMongoReplicaSetName => 'Replica Set Name';

  @override
  String get connectionMongoReplicaSetNameRequired =>
      'Replica set name is required';

  @override
  String get connectionMongoModeAdvanced => 'Advanced (Connection String)';

  @override
  String get connectionMongoModeSharded => 'Sharded (mongos)';

  @override
  String get connectionMongoMongosHosts => 'mongos Routers';

  @override
  String get connectionMongoMongosHostsHint =>
      'List all mongos router nodes (host:port, one per line). The driver connects through mongos; sharding is transparent.';

  @override
  String get connectionMongoMongosHostsRequired =>
      'At least one mongos router (host:port) is required';

  @override
  String get connectionMongoInvalidHostPort =>
      'Invalid entry (expected host or host:port)';

  @override
  String get connectionMongoConnectionString => 'Connection String';

  @override
  String get connectionMongoConnectionStringHint =>
      'Paste a full connection string (mongodb:// or mongodb+srv://, incl. Atlas). Credentials are stripped automatically; the password is stored encrypted separately.';

  @override
  String get connectionMongoConnectionStringRequired =>
      'Please paste a connection string';

  @override
  String get connectionMongoConnectionStringInvalid =>
      'Invalid connection string (must start with mongodb:// or mongodb+srv://)';

  @override
  String get connInvalidPort => 'Invalid port';

  @override
  String get connUsernameRequired => 'Username is required';

  @override
  String get connNameRequired => 'Connection name is required';

  @override
  String get connHostRequired => 'Host is required';

  @override
  String get connPortRequired => 'Port is required';

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
    return 'Failed to delete: $error';
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
  String get sidebarDropEvent => 'Drop Event';

  @override
  String sidebarDropEventConfirm(String name) {
    return 'Are you sure you want to drop event \"$name\"?';
  }

  @override
  String sidebarEventOperationFailed(String error) {
    return 'Event operation failed: $error';
  }

  @override
  String get sidebarEventNoDefinition => 'No definition';

  @override
  String get sidebarDropSynonym => 'Drop Synonym';

  @override
  String sidebarDropSynonymConfirm(String name) {
    return 'Are you sure you want to drop synonym \"$name\"?';
  }

  @override
  String sidebarSynonymOperationFailed(String error) {
    return 'Synonym operation failed: $error';
  }

  @override
  String get sidebarEnableEvent => 'Enable';

  @override
  String get sidebarDisableEvent => 'Disable';

  @override
  String get sidebarEventProperties => 'Properties';

  @override
  String get sidebarSynonyms => 'Synonyms';

  @override
  String get sidebarBrowseSynonym => 'Browse';

  @override
  String get sidebarScriptSynonymAsSelect => 'Script as SELECT';

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
  String get viewMenuTitle => 'View';

  @override
  String get viewMenuToggleSidebar => 'Sidebar';

  @override
  String get viewMenuToggleAiPanel => 'AI Panel';

  @override
  String get viewMenuToggleBottomPanel => 'Bottom Panel';

  @override
  String get viewMenuExpandWorkspace => 'Expand Workspace';

  @override
  String get viewMenuLayoutPresets => 'Layout Presets';

  @override
  String get viewMenuLayoutPresetDefault => 'Default';

  @override
  String get viewMenuLayoutPresetExpand => 'Expand Workspace';

  @override
  String get expandWorkspaceEnabled => 'Expand Workspace';

  @override
  String get expandWorkspaceDisabled => 'Exit Expand Workspace';

  @override
  String get bottomPanelTabResults => 'Results';

  @override
  String get bottomPanelTabLogs => 'Logs';

  @override
  String get bottomPanelTabHistory => 'History';

  @override
  String get bottomPanelTabTasks => 'Tasks';

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
  String get queryHistoryTitle => 'Query History';

  @override
  String get queryHistoryEmpty => 'No queries yet — run a query to see it here';

  @override
  String get queryHistoryLoading => 'Loading history...';

  @override
  String get queryHistorySearchHint => 'Search history...';

  @override
  String get queryHistoryExecutedAt => 'Executed At';

  @override
  String get queryHistorySqlPreview => 'SQL Preview';

  @override
  String get queryHistoryDuration => 'Duration';

  @override
  String get queryHistoryRowCount => 'Row Count';

  @override
  String get queryHistoryStatusSuccess => 'Success';

  @override
  String get queryHistoryStatusError => 'Error';

  @override
  String get queryHistoryClearAll => 'Clear all history';

  @override
  String get queryHistoryDelete => 'Delete';

  @override
  String get queryHistoryRename => 'Rename';

  @override
  String get queryHistoryConfirmClearAll =>
      'Are you sure you want to clear all history for this connection?';

  @override
  String queryHistoryConfirmDelete(String name) {
    return 'Are you sure you want to delete \"$name\"?';
  }

  @override
  String get queryHistoryToday => 'Today';

  @override
  String get queryHistoryYesterday => 'Yesterday';

  @override
  String get queryHistoryLast7Days => 'Last 7 days';

  @override
  String get queryHistoryOlder => 'Older';

  @override
  String get queryHistorySaved => 'Saved';

  @override
  String get resultHistorySubTabLabel => 'History';

  @override
  String get dmlCriticalTitle => 'Critical Risk Operation';

  @override
  String get dmlHighWarningTitle => 'High Risk Operation';

  @override
  String get dmlHighWarningBody =>
      'This operation will affect all matching rows. Consider adding a LIMIT clause.';

  @override
  String get dmlAddLimit => 'Add LIMIT';

  @override
  String get dmlConfirmExecute => 'Confirm Execution';

  @override
  String get dmlRiskSummary => 'Risk Summary';

  @override
  String get dmlStatementsToExecute => 'Statements to execute:';

  @override
  String dmlEstimatedAffectedRows(Object count) {
    return 'Estimated affected rows: $count';
  }

  @override
  String dmlSqlInjectionDetail(Object details) {
    return 'SQL Injection: $details';
  }

  @override
  String get dmlTriggerDeleteWithoutWhere => 'DELETE without WHERE clause';

  @override
  String get dmlTriggerUpdateWithoutWhere => 'UPDATE without WHERE clause';

  @override
  String get dmlTriggerDropTable => 'DROP TABLE operation';

  @override
  String get dmlTriggerDropDatabase => 'DROP DATABASE operation';

  @override
  String get dmlTriggerTruncateTable => 'TRUNCATE TABLE operation';

  @override
  String get dmlTriggerDmlWithoutLimit => 'DML without LIMIT clause';

  @override
  String get dmlTriggerAlterDropColumn => 'ALTER TABLE DROP COLUMN';

  @override
  String get dmlTriggerSqlInjection => 'SQL injection pattern detected';

  @override
  String dropTableDeleteConfirmBody(Object tableName) {
    return 'Are you sure you want to delete table \"$tableName\"?';
  }

  @override
  String get dropTableDeleteImpact =>
      'This operation cannot be undone. All data in the table will be permanently deleted.';

  @override
  String get dropTableCheckingDependencies => 'Checking dependencies...';

  @override
  String get dropTableDependencyWarning => 'Dependency Warning';

  @override
  String get connectionReadOnlyMode => 'Read-Only Mode';

  @override
  String get connectionReadOnlyModeDesc =>
      'Prohibit INSERT/UPDATE/DELETE/DDL operations';

  @override
  String get connectionSshHost => 'SSH Host';

  @override
  String get connectionSshUsername => 'SSH Username';

  @override
  String get connectionSshPassword => 'SSH Password';

  @override
  String get connSshHostRequired => 'SSH host is required';

  @override
  String get commonNavigate => 'Navigate';

  @override
  String get resultsSqlStatementLabel => 'SQL statement:';

  @override
  String get resultsExecutionSuccess => 'Executed successfully';

  @override
  String resultsAffectedRows(Object count) {
    return '$count rows affected';
  }

  @override
  String resultsElapsedMs(Object ms) {
    return 'Elapsed $ms ms';
  }

  @override
  String resultsFilterConditions(Object count) {
    return 'Filter: $count conditions';
  }

  @override
  String resultsShowingRows(Object filtered, Object total) {
    return 'Showing $filtered / $total rows';
  }

  @override
  String get resultsClearFilter => 'Clear filters';

  @override
  String get resultsNoDataGuidance =>
      'Write a query in the editor and press Ctrl+Enter (or F5) to run it';

  @override
  String get queryHistoryEmptyHint =>
      'Run a query with Ctrl+Enter or F5 and it will appear here automatically';

  @override
  String get safetyExplainWarning => 'Performance Warning';

  @override
  String safetyExplainFullScan(Object rows) {
    return 'Full table scan detected. Estimated $rows rows to scan.';
  }

  @override
  String get safetyExecuteAnyway => 'Execute Anyway';

  @override
  String get safetyCancelAndOptimize => 'Cancel and View Execution Plan';

  @override
  String get safetyPreflightTimeout =>
      'Preflight check timed out. Skipping performance analysis.';

  @override
  String get dmlAuditBlocked => 'DML operation blocked';

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
  String get processManagerTitle => 'Process Manager';

  @override
  String get processListNoProcesses => 'No active processes';

  @override
  String get processListNoQueryText => 'No query text';

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
  String get openSqliteFile => 'Open SQLite File…';

  @override
  String get recentFiles => 'Recent Files';

  @override
  String get recentFilesEmpty => 'No recent files';

  @override
  String get dragDropDbHint => 'Tip: drag a .db file anywhere to open it';

  @override
  String get sqliteOpenError => 'Failed to open SQLite file';

  @override
  String get sidebarServerGlobal => 'Server';

  @override
  String get sidebarPerformance => 'Performance';

  @override
  String get sidebarUsers => 'Users';

  @override
  String serverInfoVersion(String version) {
    return 'MySQL $version';
  }

  @override
  String serverInfoUptime(String duration) {
    return 'Uptime: $duration';
  }

  @override
  String serverInfoThreads(String active, String running) {
    return '$active active / $running running';
  }

  @override
  String serverInfoQueries(String count) {
    return '$count queries';
  }

  @override
  String serverInfoSlowQueries(String count) {
    return '$count slow queries';
  }

  @override
  String get serverVarMaxConnections => 'Max Connections';

  @override
  String get serverVarBufferPool => 'Buffer Pool';

  @override
  String get serverVarCharset => 'Charset';

  @override
  String get serverStatusUnavailable => 'Server status unavailable';

  @override
  String get processListRefreshLabel => 'Refresh:';

  @override
  String get processListRefreshOff => 'Off';

  @override
  String processListMore(num count) {
    return '... and $count more';
  }

  @override
  String get usersNoUsers => 'No users found';

  @override
  String get usersLocked => 'Locked';

  @override
  String sidebarDbTableCount(num count) {
    return '$count tables';
  }

  @override
  String get mongoNodeReplication => 'Replication';

  @override
  String get mongoNodeSharding => 'Sharding';

  @override
  String get mongoValidationRules => 'Validation Rules';

  @override
  String get mongoReplicationStandalone =>
      'Standalone - not part of a replica set';

  @override
  String get mongoShardingNotSharded => 'Not a sharded cluster';

  @override
  String get mongoValidationNoRules => 'No validation rules';

  @override
  String get resultColumnTruncated =>
      'Value may be truncated (large object type)';

  @override
  String get dorisUpdateGuardMessage =>
      'Doris tables with a Duplicate or Aggregate model do not support UPDATE; only Unique/Primary Key models do.';

  @override
  String get dorisTableModelLabel => 'Table model';

  @override
  String get dorisModelDuplicate => 'Duplicate';

  @override
  String get dorisModelUnique => 'Unique';

  @override
  String get dorisModelPrimaryKey => 'Primary Key';

  @override
  String get dorisHashColumnLabel => 'Hash column';

  @override
  String get dorisBucketsLabel => 'Buckets';

  @override
  String get dorisModelNeedsKeyColumn =>
      'This model requires at least one key column (mark a column as Primary Key)';

  @override
  String get dorisAggregateFunctionLabel => 'Aggregate function';

  @override
  String get dorisModelAggregate => 'Aggregate';

  @override
  String get dorisPartitionColumn => 'Partition column';

  @override
  String get dorisPartitionName => 'Partition name';

  @override
  String get dorisPartitionLessThan => 'Values less than';

  @override
  String get dorisAddPartition => 'Add partition';

  @override
  String get offlineLicenseTitle => 'Offline License';

  @override
  String get offlineLicensePurchaseHint =>
      'To upgrade: scan the payment code on our GitHub/Gitee page, then email your machine code and payment screenshot to the author. You will receive a license to import below.';

  @override
  String get machineCodeLabel => 'Machine Code';

  @override
  String get machineCodeUnavailable =>
      'Unable to read machine code on this device';

  @override
  String get importLicense => 'Import License';

  @override
  String get importLicenseHint =>
      'Paste the license string, or choose a .dbmlicense file';

  @override
  String get buyLicense => 'Buy a License';

  @override
  String get machineCodeCopied => 'Machine code copied to clipboard';

  @override
  String get licenseFilePick => 'Choose File';

  @override
  String get licenseTypeYearly => 'Yearly subscription';

  @override
  String get licenseTypeLifetime => 'Lifetime';

  @override
  String licenseExpiresAt(String date) {
    return 'Expires: $date';
  }

  @override
  String get removeLicense => 'Remove License';

  @override
  String get licenseImportSuccess =>
      'License activated — Pro features unlocked';

  @override
  String get licenseErrorInvalid => 'Invalid license format';

  @override
  String get licenseErrorSignature => 'License signature verification failed';

  @override
  String get licenseErrorMachine =>
      'This license is bound to a different machine';

  @override
  String get licenseErrorExpired => 'This license has expired';

  @override
  String get licenseErrorNoMachine =>
      'Cannot read machine code; offline licensing is unavailable on this device';

  @override
  String licenseActiveInfo(String email) {
    return 'Licensed to $email';
  }

  @override
  String get errorCopy => 'Copy';

  @override
  String get errorCopied => 'Copied';

  @override
  String get errorAnalyzeWithAi => 'Analyze with AI';

  @override
  String trialRemaining(int count, String feature) {
    return '$count trial uses left for $feature';
  }

  @override
  String trialUsedUp(String feature) {
    return '$feature trial is used up';
  }

  @override
  String get centerTitle => 'Execution Center';

  @override
  String get centerTabTasks => 'Tasks';

  @override
  String get centerTabErrors => 'Errors';

  @override
  String get centerClearErrors => 'Clear errors';

  @override
  String get centerDismissError => 'Dismiss';

  @override
  String get aiPromptErrorHeader =>
      'Diagnose this database error: explain the cause and suggest a fix.';

  @override
  String get commonUndo => 'Undo';

  @override
  String commonDeleteWithCount(Object count) {
    return 'Delete ($count)';
  }

  @override
  String aiPanelSessionsDeletedCount(Object count) {
    return 'Deleted $count conversations';
  }

  @override
  String aiPanelSessionDeleted(Object title) {
    return 'Deleted \"$title\"';
  }

  @override
  String get aiPanelSelectDatabaseRequired =>
      'Please select a database from the dropdown above first.';

  @override
  String get aiPanelMongoExecutionPlan => '🔍 Mongo Execution Plan';

  @override
  String get aiPanelSelectSessions => 'Select Sessions';

  @override
  String get aiPanelExportTaskCreated => 'Export task created successfully';

  @override
  String get aiPanelDdlOperationCancelled => 'DDL operation cancelled by user.';

  @override
  String get aiAssistantOpenTooltip => 'Open AI Assistant';

  @override
  String get schemaImpactRiskLow => 'Low Risk';

  @override
  String get schemaImpactRiskMedium => 'Medium Risk';

  @override
  String get schemaImpactRiskHigh => 'High Risk';

  @override
  String get schemaImpactRiskCritical => 'Critical Risk';

  @override
  String get schemaImpactTitle => 'Schema Impact Analysis';

  @override
  String schemaImpactSubtitle(Object table, Object type) {
    return '$type on `$table`';
  }

  @override
  String get schemaImpactDataLossWarning =>
      'Data Loss Risk: This operation will permanently delete data.';

  @override
  String schemaImpactAffectedObjects(Object count) {
    return 'Affected Objects ($count)';
  }

  @override
  String schemaImpactWarnings(Object count) {
    return 'Warnings ($count)';
  }

  @override
  String get schemaImpactRecommendations => 'Recommendations';

  @override
  String get schemaImpactHideRollbackScript => 'Hide Rollback Script';

  @override
  String get schemaImpactShowRollbackScript => 'Show Rollback Script';

  @override
  String get schemaImpactNoRollbackAvailable => 'No rollback available';

  @override
  String get schemaImpactRollbackCaveat =>
      'Auto-generated rollback is a best-effort draft - column types and constraints may be wrong. Verify before running; data cannot be auto-recovered.';

  @override
  String get schemaImpactBackupRequired =>
      'Data backup required before rollback';

  @override
  String get schemaImpactConfirmationRequired =>
      'This operation requires your explicit confirmation before execution.';

  @override
  String get ddlConfirmDialogTitle => 'DDL Confirmation Required';

  @override
  String ddlAffectedObjectsCount(Object count) {
    return 'Affected Objects ($count)';
  }

  @override
  String get ddlExecuteButton => 'Execute DDL';

  @override
  String get ddlSqlStatementLabel => 'SQL Statement:';

  @override
  String ddlRiskLevelLabel(Object level) {
    return 'Risk Level: $level';
  }

  @override
  String get ddlDataLossRiskDetected => 'Data loss risk detected';

  @override
  String ddlWarningsCount(Object count) {
    return 'Warnings ($count)';
  }

  @override
  String get ddlTypeConfirmationToProceed => 'Type confirmation to proceed';

  @override
  String ddlTypeToConfirmDestructive(Object token) {
    return 'Type \"$token\" to confirm this destructive operation:';
  }

  @override
  String get commonUnknown => 'Unknown';

  @override
  String get commonDismiss => 'Dismiss';

  @override
  String get readOnlyModeBlocked =>
      'This connection is in read-only mode; write operations are disabled.';

  @override
  String get dlgFillVariables => 'Fill in Variables';

  @override
  String dlgVariableRequired(String variable) {
    return 'Please enter $variable';
  }

  @override
  String get dlgEditTrigger => 'Edit Trigger';

  @override
  String get dlgCreateTrigger => 'Create Trigger';

  @override
  String triggerLoadTablesFailed(String error) {
    return 'Failed to load tables: $error';
  }

  @override
  String get triggerSelectTableRequired => 'Please select a table';

  @override
  String get triggerSelectEventRequired => 'Please select at least one event';

  @override
  String get triggerUpdated => 'Trigger updated successfully';

  @override
  String get triggerCreated => 'Trigger created successfully';

  @override
  String triggerSaveFailed(String error) {
    return 'Failed to save trigger: $error';
  }

  @override
  String get triggerNameLabel => 'Trigger Name';

  @override
  String get triggerNameRequired => 'Trigger name is required';

  @override
  String get triggerNameInvalid => 'Invalid trigger name format';

  @override
  String get triggerTimingLabel => 'Timing';

  @override
  String get triggerEventLabel => 'Event';

  @override
  String get triggerTableLabel => 'Table';

  @override
  String get triggerSelectTableHint => 'Select a table';

  @override
  String get triggerBodyLabel => 'Trigger Body';

  @override
  String get triggerBodyHint =>
      'Enter trigger body (SQL statements)\nExample:\nSET NEW.updated_at = NOW();';

  @override
  String triggerCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count triggers',
      one: '1 trigger',
    );
    return '$_temp0';
  }

  @override
  String get dlgExecutionResult => 'Execution Result';

  @override
  String dlgExecuteRoutine(String type) {
    return 'Execute $type';
  }

  @override
  String dlgRoutineName(String name) {
    return 'Name: $name';
  }

  @override
  String dlgRoutineType(String type) {
    return 'Type: $type';
  }

  @override
  String dlgRoutineReturnType(String type) {
    return 'Return Type: $type';
  }

  @override
  String get dlgParameters => 'Parameters';

  @override
  String get dlgRoutineNoParams =>
      'This procedure/function requires no parameters';

  @override
  String get dlgOutputParam => 'Output Parameter';

  @override
  String get dlgReturnValueLabel => 'Return Value:';

  @override
  String dlgRowsAffected(int count) {
    return 'Rows affected: $count';
  }

  @override
  String dlgEditRoutine(String type) {
    return 'Edit $type';
  }

  @override
  String routineParameterCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count parameters',
      one: '1 parameter',
      zero: 'No parameters',
    );
    return '$_temp0';
  }

  @override
  String routineDeleteConfirmation(String type, String name) {
    return 'Delete $type \"$name\"?';
  }

  @override
  String get routineListTitle => 'Procedures & Functions';

  @override
  String routineDefinitionTitle(String type) {
    return '$type Definition';
  }

  @override
  String get queryExecutionPlan => 'Query Execution Plan';

  @override
  String dlgCreateRoutine(String type) {
    return 'Create $type';
  }

  @override
  String get dlgNameRequired => 'Name is required';

  @override
  String get dlgRoutineNameInvalid =>
      'Name can only contain letters, digits and underscores, and cannot start with a digit';

  @override
  String get dlgReturnTypeRequired => 'Please select a return type';

  @override
  String get dlgSqlCode => 'SQL Code';

  @override
  String get dlgRoutineProcedure => 'Stored Procedure';

  @override
  String get dlgRoutineFunction => 'Function';

  @override
  String get commonUpdate => 'Update';

  @override
  String get commonCreate => 'Create';

  @override
  String get auditLogTitle => 'Query Audit Log';

  @override
  String get auditLogAllStatus => 'All Status';

  @override
  String get auditLogAll => 'All';

  @override
  String get auditLogTime => 'Time';

  @override
  String get auditLogDuration => 'Duration';

  @override
  String get auditLogRows => 'Rows';

  @override
  String get auditLogStatus => 'Status';

  @override
  String get auditLogEmpty => 'No audit logs yet';

  @override
  String get auditLogEmptyHint => 'Execute queries to start recording logs';

  @override
  String get auditLogTotal => 'Total';

  @override
  String get auditLogWrite => 'Write';

  @override
  String get auditLogAvgTime => 'Avg Time';

  @override
  String get auditLogClearTitle => 'Clear Audit Logs';

  @override
  String get auditLogClearConfirm =>
      'Are you sure you want to clear all audit logs? This action cannot be undone.';

  @override
  String get auditLogClear => 'Clear';

  @override
  String get piiMaskingTitle => 'PII Data Masking';

  @override
  String get piiMaskingEnable => 'Enable PII Masking';

  @override
  String get piiMaskingEnableDesc =>
      'Automatically mask sensitive data in query results';

  @override
  String get piiMaskingTypes => 'Sensitive Data Types';

  @override
  String get piiTypeEmail => 'Email Addresses';

  @override
  String get piiTypePhone => 'Phone Numbers';

  @override
  String get piiTypeIdCard => 'ID Cards';

  @override
  String get piiTypeCreditCard => 'Credit Cards';

  @override
  String get piiTypeBankCard => 'Bank Accounts';

  @override
  String get piiTypePassword => 'Passwords';

  @override
  String get piiTypeIpAddress => 'IP Addresses';

  @override
  String get shortcutNoMatching => 'No matching shortcuts';

  @override
  String get shortcutPressEscToClose => 'Press ESC to close';

  @override
  String get indexTypePrimary => 'Primary';

  @override
  String get performanceAnalyzerWeeklyReportTitle =>
      'Weekly slow query reports';

  @override
  String get performanceAnalyzerWeeklyReportDesc =>
      'Get top-10 slow queries with EXPLAIN analysis every Monday';

  @override
  String get performanceAnalyzerLearnMore => 'Learn more';

  @override
  String get backupListLoading => 'Loading backup list...';

  @override
  String dbPropertiesTitle(String name) {
    return 'Database Properties - $name';
  }

  @override
  String get dbPropertyName => 'Name';

  @override
  String get dbPropertyCharset => 'Charset';

  @override
  String get dbPropertyCollation => 'Collation';

  @override
  String get dbPropertySize => 'Size';

  @override
  String get dbPropertyTableCount => 'Tables';

  @override
  String get dbPropertyViewCount => 'Views';

  @override
  String get dbPropertyRoutineCount => 'Procedures/Functions';

  @override
  String get exportFormatLabel => 'Export Format';

  @override
  String exportRowCount(int count) {
    return '$count rows total';
  }

  @override
  String get taskCreateExportFilter => 'Filter';

  @override
  String get taskCreateExportEstRows => 'Estimated Rows';

  @override
  String get taskCreateExportValidating => 'Validating...';

  @override
  String get taskCreateExportSaveDialogTitle =>
      'Select save location for export file';

  @override
  String taskValidationPathNotExists(String path) {
    return 'Directory does not exist: $path';
  }

  @override
  String taskCreateExportDesc(String table) {
    return 'Export $table';
  }

  @override
  String taskCreateExportDescFiltered(String table) {
    return 'Export $table (filtered)';
  }

  @override
  String get sqliteConnectionEditTitle => 'Edit SQLite Connection';

  @override
  String get sqliteConnectionNewTitle => 'New SQLite Connection';

  @override
  String get createSuperTableTitle => 'Create SuperTable';

  @override
  String get importWizardTitle => 'Data Import Wizard';

  @override
  String dbCreateSuccess(String name) {
    return 'Database \"$name\" created successfully';
  }

  @override
  String get dbCreateFailed => 'Failed to create database';

  @override
  String dbCreateError(String error) {
    return 'Error: $error';
  }

  @override
  String get dbOperationCannotBeUndone => 'This operation cannot be undone!';

  @override
  String dropTablePermanentWarning(String table) {
    return 'Table \"$table\" and all its data will be permanently deleted.';
  }

  @override
  String get dropTableDataLossWarning =>
      'This operation cannot be undone! All data in this table will be permanently lost.';

  @override
  String get objectTypeTable => 'table';

  @override
  String get objectTypeView => 'view';

  @override
  String get commonRemove => 'Remove';

  @override
  String get commonRequired => 'Required';

  @override
  String get commonInvalidIdentifier => 'Invalid identifier';

  @override
  String get mongoValidationJsonObject => 'JSON must be an object';

  @override
  String mongoValidationInvalidJson(String error) {
    return 'Invalid JSON: $error';
  }

  @override
  String get settingsAutoLimitEnabledDesc =>
      'Automatically add LIMIT to SELECT queries';

  @override
  String get sqliteConnectionInfo => 'Connection Info';

  @override
  String get sqliteNameHint => 'My SQLite Database';

  @override
  String get connectionDirNotExists => 'Directory does not exist';

  @override
  String get indexSelectColumnRequired => 'Please select at least one column';

  @override
  String indexCreateFailed(String error) {
    return 'Failed to create index: $error';
  }

  @override
  String indexUpdateFailed(String error) {
    return 'Failed to update index: $error';
  }

  @override
  String get indexNameRequired => 'Index name is required';

  @override
  String get superTableTags => 'Tags';

  @override
  String get superTableCreated => 'SuperTable created successfully';

  @override
  String get redisLibNameCodeRequired => 'Library name and code are required';

  @override
  String get redisAdapterNotAvailable => 'Redis adapter not available';

  @override
  String get redisLibraryCreated => 'Function library created successfully';

  @override
  String redisLibraryCreateFailed(String error) {
    return 'Failed to create library: $error';
  }

  @override
  String get redisLibraryUsageHint => 'Used in #!lua name=<library>';

  @override
  String get redisInsertExample => 'Insert Example';

  @override
  String get redisCreateLibrary => 'Create Library';

  @override
  String redisKeyLoadFailed(String error) {
    return 'Failed to load key data: $error';
  }

  @override
  String get redisKeyUpdated => 'Key updated successfully';

  @override
  String redisKeySaveFailed(String error) {
    return 'Failed to save key: $error';
  }

  @override
  String get redisKeySaveChanges => 'Save Changes';

  @override
  String get serverConnectTitle => 'Connect to Server';

  @override
  String get serverConnectUrl => 'Server URL';

  @override
  String get serverUrlRequired => 'Server URL is required';

  @override
  String get serverUrlInvalid => 'Invalid URL (e.g. https://myserver:3000)';

  @override
  String get serverConnectEmail => 'Email';

  @override
  String get serverEmailRequired => 'Email is required';

  @override
  String get serverEmailInvalid => 'Invalid email';

  @override
  String get serverPasswordRequired => 'Password is required';

  @override
  String get mongoValidationFixErrors =>
      'Please fix JSON errors before applying';

  @override
  String get mongoValidationApplied => 'Validation rules applied successfully';

  @override
  String get mongoValidationRemoved => 'Validation rules removed';

  @override
  String get mongoValidationLevel => 'Validation Level';

  @override
  String get mongoValidationAction => 'Validation Action';

  @override
  String mongoValidationApplyFailed(String error) {
    return 'Failed to apply validation rules: $error';
  }

  @override
  String get indexSelectColumns => 'Select Columns';

  @override
  String get redisLibraryTitle => 'Create Function Library';

  @override
  String get redisLibraryNameLabel => 'Library Name';

  @override
  String get redisLibraryCreateFailedSyntax =>
      'Failed to create library (requires Redis 7.0+, check syntax)';

  @override
  String get redisLuaCodeLabel => 'Lua Code';

  @override
  String get redisReplaceExisting =>
      'Replace existing library with the same name (FUNCTION LOAD REPLACE)';

  @override
  String get redisLibraryInfoText =>
      'Library name is written into the #!lua shebang automatically. Lua code should contain redis.register_function() calls. Do not write the shebang yourself.';

  @override
  String get superTableCreateFailed => 'Failed to create SuperTable';

  @override
  String get superTableColumns => 'Columns';

  @override
  String get errorTitle => 'An error occurred';

  @override
  String get errorDescriptionLabel => 'Error details:';

  @override
  String get errorStackLabel => 'Stack trace:';

  @override
  String get columnFilterTypeNumeric => 'Numeric';

  @override
  String get columnFilterTypeDateTime => 'Date/Time';

  @override
  String get columnFilterTypeText => 'Text';

  @override
  String get columnFilterPlaceholderNumeric => 'Enter a number';

  @override
  String get columnFilterPlaceholderDateTime => 'Enter date (e.g., 2024-01-01)';

  @override
  String get columnFilterPlaceholderText => 'Enter text';

  @override
  String columnFilterFor(String columnName) {
    return 'Filter: $columnName';
  }

  @override
  String columnFilterActive(int count) {
    return '$count active filter conditions';
  }

  @override
  String columnFilterRowCount(String filtered, String total) {
    return '$filtered / $total rows';
  }

  @override
  String get filterOpEquals => 'equals';

  @override
  String get filterOpNotEquals => 'not equals';

  @override
  String get filterOpContains => 'contains';

  @override
  String get filterOpNotContains => 'not contains';

  @override
  String get filterOpStartsWith => 'starts with';

  @override
  String get filterOpEndsWith => 'ends with';

  @override
  String get filterOpGreaterThan => 'greater than';

  @override
  String get filterOpGreaterThanOrEqual => 'greater than or equal';

  @override
  String get filterOpLessThan => 'less than';

  @override
  String get filterOpLessThanOrEqual => 'less than or equal';

  @override
  String get filterOpBetween => 'between';

  @override
  String get filterOpIsNull => 'is null';

  @override
  String get filterOpIsNotNull => 'is not null';

  @override
  String get filterOpIsEmpty => 'is empty';

  @override
  String get filterOpIsNotEmpty => 'is not empty';

  @override
  String get tableNoData => 'No data';

  @override
  String tableRowCountTotal(String count) {
    return '$count total rows';
  }

  @override
  String get tableLargeDatasetHint => '(Large dataset, scroll to load more)';

  @override
  String tableRowRange(String start, String end, String total) {
    return '$start-$end / $total rows';
  }

  @override
  String get importWizStepSelectFile => 'Select File';

  @override
  String get importWizStepAnalyzeFile => 'Analyze File';

  @override
  String get importWizStepColumnMapping => 'Column Mapping';

  @override
  String get importWizStepPreviewPII => 'Preview & PII';

  @override
  String get importWizStepConfirmImport => 'Confirm Import';

  @override
  String importWizStepOf(String current, String total, String title) {
    return 'Step $current of $total: $title';
  }

  @override
  String get importWizTargetDatabase => 'Target Database';

  @override
  String get importWizSelectDatabase => 'Select database';

  @override
  String get importWizTargetTableOptional => 'Target Table (optional)';

  @override
  String get importWizLetAiInfer => '-- Let AI infer table name --';

  @override
  String get importWizChooseFile => 'Click to select file or drag here';

  @override
  String get importWizChangeFile => 'Change file';

  @override
  String get importWizSupportedFormats =>
      'Supports CSV, JSON, Excel, TSV formats';

  @override
  String get importWizFileUnknown => 'Unknown';

  @override
  String get importWizAiAnalyzing => 'AI is analyzing file...';

  @override
  String get importWizDetectingFormat =>
      'Detecting format, encoding, field types...';

  @override
  String get importWizFileAnalysisResult => 'File Analysis Result';

  @override
  String get importWizFormat => 'Format';

  @override
  String get importWizEncoding => 'Encoding';

  @override
  String get importWizFieldCount => 'Fields';

  @override
  String get importWizEstimatedRows => 'Est. rows';

  @override
  String get importWizFileSize => 'File size';

  @override
  String get importWizDelimiter => 'Delimiter';

  @override
  String get importWizDetectedFields => 'Detected Fields';

  @override
  String get importWizAiSuggestion => 'AI Suggestion';

  @override
  String importWizTargetTableName(String tableName) {
    return 'Target table: $tableName';
  }

  @override
  String get importWizNoAnalysisResult => 'No analysis result';

  @override
  String get importWizSelectFileFirst => 'Please select a file first';

  @override
  String get importWizNoColumnMapping => 'No column mapping';

  @override
  String get importWizGeneratingMapping => 'Generating mapping...';

  @override
  String get importWizColumnMappingConfig => 'Column Mapping Configuration';

  @override
  String importWizColumnsMapped(String mapped, String total) {
    return '$mapped/$total columns mapped';
  }

  @override
  String get importWizMappingDescription =>
      'Map file columns to database table columns. Select \"Skip\" to skip a column.';

  @override
  String get importWizFileColumn => 'File Column';

  @override
  String get importWizDatabaseColumn => 'Database Column';

  @override
  String get importWizType => 'Type';

  @override
  String get importWizPiiDetection => 'PII Sensitive Data Detection';

  @override
  String get importWizPiiDetectionMessage =>
      'The following sensitive fields were detected. Please confirm whether to continue the import:';

  @override
  String get importWizPiiAcknowledge => 'I understand, continue import';

  @override
  String get importWizDataPreview => 'Data Preview';

  @override
  String importWizWarnings(String count) {
    return '$count warnings';
  }

  @override
  String importWizFirstRows(String count) {
    return 'First $count rows';
  }

  @override
  String get importWizSensitiveField => 'Sensitive field';

  @override
  String get importWizDataValidationWarnings => 'Data Validation Warnings';

  @override
  String importWizValidationRowFormat(String row, String col, String msg) {
    return 'Row $row, Col $col: $msg';
  }

  @override
  String get importWizImportSummary => 'Import Configuration Summary';

  @override
  String get importWizSummaryTargetDatabase => 'Target database';

  @override
  String get importWizSummaryTargetTable => 'Target table';

  @override
  String get importWizSummaryFile => 'File';

  @override
  String get importWizSummaryMappedColumns => 'Mapped columns';

  @override
  String get importWizSummaryDataRows => 'Data rows';

  @override
  String get importWizConflictStrategy => 'Conflict Resolution Strategy';

  @override
  String get importWizConflictSkip => 'Skip duplicates';

  @override
  String get importWizConflictSkipDesc =>
      'When a duplicate key is encountered, skip the row and continue importing';

  @override
  String get importWizConflictUpdate => 'Update existing rows';

  @override
  String get importWizConflictUpdateDesc =>
      'When a duplicate key is encountered, update the existing data';

  @override
  String get importWizConflictAbort => 'Abort import';

  @override
  String get importWizConflictAbortDesc =>
      'When a duplicate key is encountered, stop the import immediately';

  @override
  String get importWizConflictSkipName => 'Skip duplicates';

  @override
  String get importWizConflictUpdateName => 'Update existing';

  @override
  String get importWizConflictAbortName => 'Abort';

  @override
  String get importWizImporting => 'Importing...';

  @override
  String importWizRowsProgress(String imported, String total) {
    return '$imported/$total rows';
  }

  @override
  String importWizFailedRows(String count) {
    return 'Failed: $count rows';
  }

  @override
  String get importWizImportComplete => 'Import Complete!';

  @override
  String importWizImportFailed(String error) {
    return 'Import failed: $error';
  }

  @override
  String importWizImportSuccessMsg(String count) {
    return 'Successfully imported $count rows';
  }

  @override
  String get importWizImportErrorMsg => 'An error occurred during import';

  @override
  String get importWizPreviousStep => 'Previous';

  @override
  String get importWizClose => 'Close';

  @override
  String get importWizStartImport => 'Start Import';

  @override
  String get importWizNextStep => 'Next';

  @override
  String get importWizReimport => 'Re-import';

  @override
  String importWizLoadDatabasesFailed(String error) {
    return 'Failed to load database list: $error';
  }

  @override
  String importWizLoadTablesFailed(String error) {
    return 'Failed to load table list: $error';
  }

  @override
  String importWizPickFileFailed(String error) {
    return 'Failed to select file: $error';
  }

  @override
  String importWizAnalysisFailed(String error) {
    return 'Analysis failed: $error';
  }

  @override
  String importWizMappingFailed(String error) {
    return 'Failed to generate column mapping: $error';
  }

  @override
  String get importWizFileAnalysisFailed => 'File analysis failed';

  @override
  String get importWizImportFailedGeneric => 'Import failed';

  @override
  String get importWizNotSelected => 'Not selected';

  @override
  String get importWizNotSet => 'Not set';

  @override
  String get importWizUnknown => 'Unknown';

  @override
  String get importWizPiiDetectionSummary => 'PII Detection';

  @override
  String importWizSensitiveFieldCount(String count) {
    return '$count sensitive fields';
  }

  @override
  String get smartImportAnalyzingDetail =>
      'AI is identifying field types and generating CREATE TABLE statement';

  @override
  String get smartImportColumnMapping => 'Column Mapping';

  @override
  String smartImportColumnsMapped(String mapped, String total) {
    return '$mapped/$total columns mapped';
  }

  @override
  String get smartImportFileColumn => 'File Column';

  @override
  String get smartImportTableColumn => 'Table Column';

  @override
  String get smartImportConflictResolution => 'Conflict Resolution';

  @override
  String get smartImportDataPreview => 'Data Preview';

  @override
  String smartImportFirstRows(String count) {
    return 'First $count rows';
  }

  @override
  String get smartImportBack => 'Back';

  @override
  String get smartImportBackgroundTask => 'Background Import';

  @override
  String get smartImportFailedToGenerateSql =>
      '-- Failed to generate CREATE TABLE statement';

  @override
  String smartImportTargetTableSelected(String table) {
    return 'Target table selected: $table';
  }

  @override
  String smartImportTargetTableEntered(String table) {
    return 'Target table entered: $table';
  }

  @override
  String smartImportAnalysisFailed(String error) {
    return 'File analysis failed: $error';
  }

  @override
  String smartImportColumnMappingsComplete(String mapped, String total) {
    return 'Column mapping complete: $mapped/$total columns auto-matched';
  }

  @override
  String smartImportPiiDetected(String types) {
    return 'PII Detection: Sensitive fields found - $types';
  }

  @override
  String get smartImportPiiNone => 'PII Detection: No sensitive fields found';

  @override
  String smartImportPiiFailed(String error) {
    return 'PII Detection failed: $error';
  }

  @override
  String smartImportPreviewGenerated(String count) {
    return 'Data preview generated ($count rows)';
  }

  @override
  String smartImportPreviewFailed(String error) {
    return 'Failed to generate preview: $error';
  }

  @override
  String smartImportMappingFailed(String error) {
    return 'Failed to generate column mapping: $error';
  }

  @override
  String importServiceStartImport(String table) {
    return 'Starting data import to table \"$table\"...';
  }

  @override
  String importServiceColumnMapping(String mapped, String total) {
    return 'Column mapping: $mapped/$total columns mapped';
  }

  @override
  String importServiceConflictStrategy(String strategy) {
    return 'Conflict resolution strategy: $strategy';
  }

  @override
  String get importServiceImporting => 'Starting data import...';

  @override
  String importServiceBatchSuccess(String batch, String count) {
    return 'Batch $batch: Successfully imported $count rows';
  }

  @override
  String importServiceBatchInsertFailed(String count) {
    return 'Batch insert failed ($count rows), trying row-by-row...';
  }

  @override
  String importServiceUpdateFailed(String error) {
    return 'Update failed: $error';
  }

  @override
  String importServiceDataTooLong(String row) {
    return 'Row $row data too long, skipped';
  }

  @override
  String importServiceRowInsertFailed(String row, String error) {
    return 'Row $row insert failed: $error';
  }

  @override
  String importServiceBatchSkipped(String count) {
    return 'Batch skipped: $count rows (duplicates)';
  }

  @override
  String importServiceBatchUpdated(String count) {
    return 'Batch updated: $count rows';
  }

  @override
  String importServiceBatchFailed(String count) {
    return 'Batch failed: $count rows';
  }

  @override
  String importServicePhaseProgress(
    String imported,
    String skipped,
    String updated,
  ) {
    return 'Imported $imported rows, skipped $skipped rows, updated $updated rows...';
  }

  @override
  String get importServiceImportCancelled => 'Import cancelled';

  @override
  String importServiceFileReadFailed(String error) {
    return 'File read failed: $error';
  }

  @override
  String importServiceImportComplete(String imported, String failed) {
    return 'Import complete! Success: $imported rows, Failed: $failed rows';
  }

  @override
  String taskExecutorAnalyzeFile(String path) {
    return 'Analyzing file: $path';
  }

  @override
  String taskExecutorFileFormat(String format, String encoding, String rows) {
    return 'File format: $format, Encoding: $encoding, Estimated rows: $rows';
  }

  @override
  String get taskExecutorTableNotExists => 'Table does not exist, creating...';

  @override
  String get taskExecutorTableCreated => 'Table created successfully';

  @override
  String get taskExecutorTableCreateFailed => 'Failed to create table';

  @override
  String taskExecutorTableNotExistsError(String table) {
    return 'Target table \"$table\" does not exist. Please create the table first.';
  }

  @override
  String get taskExecutorNoColumnMapping =>
      'No usable column mapping. Please check that file fields match table fields.';

  @override
  String taskExecutorColumnMapping(String mapped, String total) {
    return 'Column mapping: $mapped/$total columns mapped';
  }

  @override
  String get taskExecutorStartImport => 'Starting data import...';

  @override
  String taskExecutorImportComplete(String imported, String failed) {
    return 'Import complete! Success: $imported rows, Failed: $failed rows';
  }

  @override
  String get taskExecutorImportFinished => 'Import complete';

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
  String get driftMenuLabel => 'Schema Drift Alerts';

  @override
  String get driftTaskListTitle => 'Schema Drift Alerts';

  @override
  String get driftTaskListEmpty =>
      'No drift tasks yet. Create one to monitor a source database for schema changes.';

  @override
  String get driftTaskListEmptyHint =>
      'Drift tasks snapshot a read-only source database on a schedule and alert you when the schema changes.';

  @override
  String get driftCreateTaskButton => 'New Drift Task';

  @override
  String get driftRunNowButton => 'Run Now';

  @override
  String get driftHistoryButton => 'History';

  @override
  String get driftViewDiffButton => 'View Diff';

  @override
  String get driftDeleteTaskButton => 'Delete';

  @override
  String get driftColTaskName => 'Task';

  @override
  String get driftColSource => 'Source database';

  @override
  String get driftColInterval => 'Interval';

  @override
  String get driftColLastRun => 'Last run';

  @override
  String get driftColStatus => 'Status';

  @override
  String driftIntervalMinutes(String minutes) {
    return 'Every $minutes min';
  }

  @override
  String driftIntervalHours(String hours) {
    return 'Every $hours h';
  }

  @override
  String get driftIntervalUnknown => 'Server default';

  @override
  String get driftEditIntervalTooltip => 'Edit check interval';

  @override
  String get driftEditIntervalTitle => 'Edit Check Interval';

  @override
  String get driftIntervalUpdated =>
      'Interval updated. It applies from the next scheduled scan.';

  @override
  String get driftStatusNever => 'Never run';

  @override
  String get driftStatusRunning => 'Running';

  @override
  String get driftStatusSucceeded => 'Succeeded';

  @override
  String get driftStatusFailed => 'Failed';

  @override
  String get driftStatusUnknown => 'Unknown';

  @override
  String get driftCreateTaskTitle => 'Create Drift Task';

  @override
  String get driftCreateTaskName => 'Task name';

  @override
  String get driftCreateTaskSource => 'Source connection (read-only)';

  @override
  String get driftCreateTaskNoSources => 'No read-only source connections yet.';

  @override
  String get driftCreateTaskAddSource => 'Add a source connection';

  @override
  String get driftCreateTaskInterval => 'Check interval';

  @override
  String get driftCreateTaskWebhook => 'Webhook URL (optional, https)';

  @override
  String get driftCreateTaskWebhookHint =>
      'Feishu / DingTalk / Slack webhook — comma-separated for multiple';

  @override
  String get driftCreateTaskSubmit => 'Create Task';

  @override
  String get driftCreateTaskInvalidName => 'Enter a task name.';

  @override
  String get driftCreateTaskInvalidSource => 'Select a source connection.';

  @override
  String get driftCreateTaskInvalidInterval =>
      'Interval must be between 1 and 1440 minutes.';

  @override
  String get driftCreateTaskInvalidWebhook =>
      'Webhook URL must start with https://';

  @override
  String get driftGatedTitle => 'Server license gated';

  @override
  String get driftGatedBody =>
      'Activate or renew the Server license to create or run drift tasks. Existing data is still visible.';

  @override
  String get driftCreateSourceTitle => 'Add Read-Only Source Connection';

  @override
  String get driftCreateSourceDbType => 'Database type';

  @override
  String get driftCreateSourceHost => 'Host';

  @override
  String get driftCreateSourcePort => 'Port';

  @override
  String get driftCreateSourceUsername => 'Username (read-only account)';

  @override
  String get driftCreateSourcePassword => 'Password';

  @override
  String get driftCreateSourceDatabase => 'Database (optional)';

  @override
  String get driftCreateSourceSubmit => 'Add Connection';

  @override
  String get driftCreateSourceCanaryNote =>
      'The Server probes the account before saving — writable accounts are rejected. Use a SELECT-only account.';

  @override
  String get driftRunQueued =>
      'Run queued. The list updates automatically when the run completes.';

  @override
  String driftRunFailed(String error) {
    return 'Run failed: $error';
  }

  @override
  String get driftHistoryTitle => 'Run History';

  @override
  String get driftHistoryColStarted => 'Started';

  @override
  String get driftHistoryColDuration => 'Duration';

  @override
  String get driftHistoryColDrift => 'Drift';

  @override
  String get driftHistoryColTrigger => 'Trigger';

  @override
  String get driftHistoryColWebhook => 'Webhook';

  @override
  String get driftHistoryNoDrift => 'No drift';

  @override
  String driftHistoryHasDrift(String count) {
    return '$count change(s)';
  }

  @override
  String driftHistoryError(String error) {
    return 'Error: $error';
  }

  @override
  String get driftTriggerManual => 'Manual';

  @override
  String get driftTriggerScheduler => 'Scheduler';

  @override
  String get driftDiffTitle => 'Drift Diff';

  @override
  String get driftDiffPickSnapshots => 'Pick two snapshots to compare';

  @override
  String get driftDiffSnapshotNewer => 'Newer';

  @override
  String get driftDiffSnapshotOlder => 'Older';

  @override
  String get driftDiffCompare => 'Compare';

  @override
  String get driftDiffNoComparable =>
      'Pick two different snapshots to compare.';

  @override
  String get driftDiffEmpty => 'No changes between these two snapshots.';

  @override
  String get driftLoading => 'Loading…';

  @override
  String get driftRetry => 'Retry';

  @override
  String get driftClose => 'Close';

  @override
  String get viewModeTable => 'Table';

  @override
  String get viewModeChart => 'Chart';

  @override
  String get viewModeCard => 'Card';

  @override
  String get viewModeDocument => 'Documents';

  @override
  String get viewModeJsonTree => 'JSON Tree';

  @override
  String get viewModeKeyValue => 'Key-Value';

  @override
  String get documentExpand => 'Expand';

  @override
  String get documentCollapse => 'Collapse';

  @override
  String documentExpandMore(int count) {
    return 'Expand $count more fields';
  }

  @override
  String jsonTreeItemCount(int count) {
    return '$count items';
  }

  @override
  String get keyValueField => 'Field';

  @override
  String get keyValueValue => 'Value';

  @override
  String keyValueFieldLabel(String field) {
    return 'Field: $field';
  }

  @override
  String keyValueLengthLabel(int length) {
    return 'Length: $length chars';
  }

  @override
  String get chartViewComingSoon => 'Chart view (coming soon)';

  @override
  String chartExportSuccess(String path) {
    return 'Chart saved to $path';
  }

  @override
  String chartExportFailed(String error) {
    return 'Chart export failed: $error';
  }

  @override
  String chartSamplingNotice(int count) {
    return 'Large dataset: sampled $count points for performance';
  }

  @override
  String get chartAiTrend => 'AI Trend Analysis';

  @override
  String get chartTypeLine => 'Line';

  @override
  String get chartTypeBar => 'Bar';

  @override
  String get chartTypePie => 'Pie';

  @override
  String get chartTypeScatter => 'Scatter';

  @override
  String get statisticsPanelTitle => 'Statistics';

  @override
  String get exportStepBack => 'Back';

  @override
  String get exportStepNext => 'Next';

  @override
  String get noJsonDataToSample => 'No data to sample';

  @override
  String get noLeafNodes => 'No extractable fields';

  @override
  String get fieldNotInAllRows => 'not in all rows';

  @override
  String get commonRetry => 'Retry';

  @override
  String get extensionNoAdapter => 'No adapter';

  @override
  String get extensionNotPostgres => 'Not a PostgreSQL connection';

  @override
  String get extensionLoadFailed => 'Failed to load members';

  @override
  String get extensionTypes => 'Types';

  @override
  String get extensionFunctions => 'Functions';

  @override
  String get extensionOperators => 'Operators';

  @override
  String get extensionSchema => 'Schema';

  @override
  String get extensionDescription => 'Description';

  @override
  String get vectorLoadFailed => 'Failed to load vector indexes';

  @override
  String get vectorNoAdapter => 'No adapter';

  @override
  String get vectorNoIndexes => 'No vector indexes defined';

  @override
  String get jsonInvalidJson => 'Invalid JSON';

  @override
  String get jsonNoMatches => 'No matches';

  @override
  String get jsonSearchHint => 'Search keys or values...';

  @override
  String get jsonMaxDepthReached => '<max depth reached>';

  @override
  String get jsonTruncated => '<truncated>';

  @override
  String get commonApply => 'Apply';

  @override
  String get pragmaExplorerTitle => 'PRAGMA Explorer';

  @override
  String get pragmaNoAdapter => 'No adapter';

  @override
  String get pragmaNotSQLite =>
      'PRAGMA Explorer is only available for SQLite connections';

  @override
  String get pragmaSearchHint => 'Search PRAGMA by name or value...';

  @override
  String get pragmaCategoryPerformance => 'Performance';

  @override
  String get pragmaCategoryDurability => 'Durability';

  @override
  String get pragmaCategorySecurity => 'Security';

  @override
  String get pragmaCategoryDebug => 'Debug';

  @override
  String get pragmaSetValue => 'Set value';

  @override
  String get sqliteCopyFilePath => 'Copy File Path';

  @override
  String get sqliteOpenInFolder => 'Open in Folder';

  @override
  String get sqliteToggleWalMode => 'Toggle WAL Mode';

  @override
  String get sqliteOptimizeDatabase => 'Optimize Database';

  @override
  String get sqliteVacuum => 'VACUUM';

  @override
  String get sqliteIntegrityCheck => 'Integrity Check';

  @override
  String get sqliteSaveAs => 'Save As…';

  @override
  String get sqliteStatusWal => 'WAL';

  @override
  String get sqliteStatusPageSize => 'Page';

  @override
  String get sqliteStatusFileSize => 'File';

  @override
  String get sqliteAttachDatabase => 'Attach Database…';

  @override
  String get sqliteDetach => 'Detach';

  @override
  String get sqliteAttachFileLabel => 'Database file';

  @override
  String get sqliteAttachFileHint => 'Pick a .db file to attach';

  @override
  String get sqliteAttachPickFile => 'Pick file';

  @override
  String get sqliteAttachAliasLabel => 'Alias';

  @override
  String get sqliteAttachAliasHint => 'archive';

  @override
  String get sqliteAttachAliasHelp =>
      'Letters, digits, underscore. Used as the schema prefix in cross-database queries (e.g. SELECT * FROM alias.table).';

  @override
  String get sqliteAttachButton => 'Attach';

  @override
  String sqliteAttachSuccess(String alias) {
    return 'Attached $alias';
  }

  @override
  String sqliteAttachFailed(String error) {
    return 'Attach failed: $error';
  }

  @override
  String sqliteDetachSuccess(String alias) {
    return 'Detached $alias';
  }

  @override
  String sqliteDetachFailed(String error) {
    return 'Detach failed: $error';
  }

  @override
  String get sqliteAttachAliasInvalid =>
      'Alias must start with a letter or underscore and contain only letters, digits, underscores.';

  @override
  String get sqliteAttachAliasReserved =>
      'Alias \"main\" and \"temp\" are reserved.';

  @override
  String get sqliteAttachAliasKeyword =>
      'Alias is a SQLite keyword. Pick a different name.';

  @override
  String get sqliteAttachAliasDuplicate =>
      'An attached database with this alias already exists.';

  @override
  String get mongoNestedFields => 'Nested fields';

  @override
  String get healthMenuLabel => 'Health Check';

  @override
  String get healthDialogTitle => 'Health Check';

  @override
  String get healthDialogSubtitle =>
      'Scheduled database health monitoring (ADR-0004)';

  @override
  String get healthStatusHealthy => 'Healthy';

  @override
  String get healthStatusWarning => 'Alerts active';

  @override
  String get healthStatusCritical => 'Check failing';

  @override
  String get healthStatusUnknown => 'No data';

  @override
  String get healthNoTasks => 'No health check tasks configured.';

  @override
  String get healthNoTasksHint =>
      'Tasks are created via the Server API or admin UI.';

  @override
  String healthBadgeAlerts(int n) {
    return '$n alerts';
  }

  @override
  String get healthColumnTask => 'Task';

  @override
  String get healthColumnStatus => 'Status';

  @override
  String get healthColumnLastCheck => 'Last check';

  @override
  String get healthColumnConnection => 'Connection';

  @override
  String get healthRunNow => 'Run now';

  @override
  String get healthRunQueued => 'Run queued — refreshing in a moment.';

  @override
  String get healthRefreshFailed => 'Failed to load health results.';

  @override
  String get healthNoResults => 'No results yet';

  @override
  String get healthAgoJustNow => 'just now';

  @override
  String healthAgoMinutes(int n) {
    return '$n min ago';
  }

  @override
  String healthAgoHours(int n) {
    return '$n h ago';
  }

  @override
  String healthAgoDays(int n) {
    return '$n d ago';
  }

  @override
  String healthLatencyMs(int ms) {
    return '$ms ms';
  }

  @override
  String healthAlertsCount(int n) {
    return '$n alerts';
  }

  @override
  String get healthMetricConnectivity => 'Connectivity';

  @override
  String get healthMetricRowCount => 'Row count';

  @override
  String get healthMetricMissingPk => 'Missing primary keys';

  @override
  String get healthMetricConnectionCount => 'Connections';

  @override
  String get healthClose => 'Close';

  @override
  String get healthLoading => 'Loading…';

  @override
  String get healthResultSuccess => 'Success';

  @override
  String get healthResultPartial => 'Partial';

  @override
  String get healthResultFailed => 'Failed';

  @override
  String get healthRefresh => 'Refresh';

  @override
  String get healthCreateTaskTitle => 'Create Health Check Task';

  @override
  String get healthCreateTaskName => 'Task name';

  @override
  String get healthCreateTaskInvalidName => 'Please enter a task name.';

  @override
  String get healthCreateTaskSource => 'Source connection';

  @override
  String get healthCreateTaskNoConnections =>
      'No database connections on the server yet. Add one under \"Server connections\".';

  @override
  String get healthCreateTaskCron => 'Cron schedule';

  @override
  String get healthCreateTaskCronHint =>
      '5-field cron, e.g. */5 * * * * (every 5 minutes)';

  @override
  String get healthCreateTaskInvalidCron =>
      'Enter a valid 5-field cron expression.';

  @override
  String get healthCreateTaskFailThreshold => 'Alert threshold';

  @override
  String get healthCreateTaskFailThresholdHint =>
      'Consecutive failures before alerting (1-10)';

  @override
  String get healthCreateTaskInvalidFailThreshold =>
      'Threshold must be between 1 and 10.';

  @override
  String get healthCreateTaskWebhook => 'Webhook URL (optional)';

  @override
  String get healthCreateTaskWebhookHint =>
      'https:// URL to receive health alerts.';

  @override
  String get healthCreateTaskInvalidWebhook =>
      'Webhook must be an https:// URL.';

  @override
  String get healthCreateTaskSubmit => 'Create Task';

  @override
  String get healthCreateTaskButton => 'New Task';

  @override
  String get healthGatedTitle => 'Server license gated';

  @override
  String get healthGatedBody =>
      'Activate or renew the Server license to create health check tasks. Existing data is still visible.';

  @override
  String get healthHistoryTitle => 'Run History';

  @override
  String get healthViewAllHistory => 'View full history';

  @override
  String healthHistoryError(String error) {
    return 'Error: $error';
  }

  @override
  String get healthTriggerManual => 'Manual';

  @override
  String get healthTriggerScheduler => 'Scheduled';

  @override
  String get dataSyncCreateTaskButton => 'New Sync Task';

  @override
  String get taskEditTitle => 'Edit Task';

  @override
  String get taskEditName => 'Task name';

  @override
  String get taskEditInvalidName => 'Name cannot be empty';

  @override
  String get taskEditEnabled => 'Enabled';

  @override
  String get taskEditEnabledHint =>
      'Schedule is active (cron fires as configured)';

  @override
  String get taskEditDisabledHint => 'Paused — cron will not fire';

  @override
  String get taskEditCron => 'Cron expression';

  @override
  String get taskEditCronHint =>
      '5 fields: minute hour day month weekday (e.g. */5 * * * *)';

  @override
  String get taskEditInvalidCron => 'Enter 5 space-separated fields';

  @override
  String get taskEditWebhook => 'Webhook URL';

  @override
  String get taskEditWebhookHint =>
      'Optional HTTPS webhooks — comma-separated for multiple';

  @override
  String get taskEditInvalidWebhook => 'Must start with https://';

  @override
  String get taskEditCancel => 'Cancel';

  @override
  String get taskEditSubmit => 'Save Changes';

  @override
  String get taskTogglePauseTooltip => 'Pause schedule';

  @override
  String get taskToggleResumeTooltip => 'Resume schedule';

  @override
  String get taskEditTooltip => 'Edit task';

  @override
  String get taskDeleteTooltip => 'Delete task';

  @override
  String get taskDeleteConfirm => 'Delete this task? This cannot be undone.';

  @override
  String get teamQueryTitle => 'Team Query Library';

  @override
  String get teamQueryRefresh => 'Refresh';

  @override
  String get teamQuerySearchHint => 'Search title or SQL…';

  @override
  String get teamQueryTagHint => 'Filter by tag';

  @override
  String get teamQueryEmpty =>
      'No team queries yet. Publish one from the editor.';

  @override
  String get teamQueryNotConnected => 'Not connected to a DbMaster server.';

  @override
  String get teamQueryFork => 'Open (fork to editor)';

  @override
  String get teamQueryDelete => 'Delete';

  @override
  String get teamQueryCancel => 'Cancel';

  @override
  String teamQueryDeleteConfirm(String title) {
    return 'Delete \"$title\" from the team library?';
  }

  @override
  String get teamQueryForkNoConnection =>
      'Open a database connection first, then fork a team query.';

  @override
  String teamQueryForked(String title) {
    return 'Opened \"$title\" in a new tab.';
  }

  @override
  String teamQueryCreatedBy(String author) {
    return 'by $author';
  }

  @override
  String get teamQueryMenuLabel => 'Team Query Library';

  @override
  String get saveToTeamTooltip => 'Save to Team Library';

  @override
  String get saveToTeamTitle => 'Publish to Team Library';

  @override
  String get saveToTeamNameLabel => 'Query name';

  @override
  String get saveToTeamTagsLabel => 'Tags (comma-separated)';

  @override
  String get saveToTeamTagsHint => 'Optional — helps teammates find this query';

  @override
  String get saveToTeamCancel => 'Cancel';

  @override
  String get saveToTeamSubmit => 'Publish';

  @override
  String saveToTeamSuccess(String title) {
    return 'Published \"$title\" to the team library.';
  }

  @override
  String get saveToTeamGated =>
      'License gated — activate the Server license to publish team queries.';

  @override
  String get approvalMenuLabel => 'DDL Approvals';

  @override
  String get approvalListTitle => 'DDL Approvals';

  @override
  String get approvalAddTooltip => 'Submit new DDL';

  @override
  String get approvalRefresh => 'Refresh';

  @override
  String get approvalNotConnected =>
      'Connect to a DbMaster server to view approvals.';

  @override
  String get approvalListEmpty => 'No DDL approvals.';

  @override
  String get approvalSubmitTitle => 'Submit DDL for Approval';

  @override
  String get approvalSubmitButton => 'Submit for Approval';

  @override
  String get approvalSubmitDdlLabel => 'DDL Statement';

  @override
  String get approvalSubmitDdlHint => 'Paste the DDL to submit for review';

  @override
  String get approvalSubmitRequired => 'DDL statement is required';

  @override
  String get approvalSubmitInvalidSql =>
      'Does not look like DDL (expected CREATE/ALTER/DROP/TRUNCATE/RENAME)';

  @override
  String get approvalSubmitTargetDb => 'Target Connection';

  @override
  String get approvalSubmitNoConnection =>
      'No server connections available. Add one under \"Server connections\".';

  @override
  String get approvalSubmitSuccess => 'DDL submitted for approval.';

  @override
  String get approvalLoading => 'Loading…';

  @override
  String get approvalCancel => 'Cancel';

  @override
  String get approvalApprove => 'Approve & Execute';

  @override
  String get approvalReject => 'Reject';

  @override
  String get approvalRejectTitle => 'Reject Approval';

  @override
  String get approvalRejectConfirm =>
      'Reject this DDL approval? The Server will not execute the DDL. This cannot be undone.';

  @override
  String get approvalViewDdl => 'View DDL';

  @override
  String get approvalStatusPending => 'Pending';

  @override
  String get approvalStatusExecuting => 'Executing';

  @override
  String get approvalStatusApproved => 'Approved';

  @override
  String get approvalStatusFailed => 'Failed';

  @override
  String get approvalStatusRejected => 'Rejected';

  @override
  String approvalExecError(String error) {
    return 'Error: $error';
  }

  @override
  String get approvalAlreadyResolved =>
      'This approval was already resolved by another reviewer.';

  @override
  String get approvalConflict =>
      'Another reviewer claimed this approval first.';

  @override
  String get approvalNotFound =>
      'Approval not found (it may have been deleted).';

  @override
  String get approvalGatedTitle => 'License Required';

  @override
  String get approvalGatedBody =>
      'Activate or renew the Server license to manage DDL approvals.';

  @override
  String approvalMetaLine(String target, String submitter) {
    return '→ $target • by $submitter';
  }

  @override
  String approvalBadgeCount(int n) {
    return '$n pending';
  }

  @override
  String get submitApprovalTooltip => 'Submit DDL for Approval';

  @override
  String get workspacesMenuLabel => 'Workspaces';

  @override
  String get workspacesTitle => 'Workspaces';

  @override
  String get workspacesRefresh => 'Refresh';

  @override
  String get workspacesCreate => 'New workspace';

  @override
  String get workspacesJoin => 'Join workspace';

  @override
  String get workspacesNotConnected =>
      'Connect to a DbMaster server to manage workspaces.';

  @override
  String get workspacesEmpty =>
      'No workspaces yet. Create one or join with an invite code.';

  @override
  String get workspacesMembers => 'Members';

  @override
  String get workspacesLeave => 'Leave';

  @override
  String get workspacesDelete => 'Delete';

  @override
  String workspacesMemberCount(int n) {
    return '$n members';
  }

  @override
  String get workspacesRoleAdmin => 'Admin';

  @override
  String get workspacesScopeNotice =>
      'Workspaces are member groups for inviting collaborators. Automation tasks, connections, and the team query library are shared across the whole server instance — they are not isolated per workspace.';

  @override
  String get workspacesRoleMember => 'Member';

  @override
  String workspacesLeaveConfirm(String name) {
    return 'Leave workspace \"$name\"?';
  }

  @override
  String workspacesDeleteConfirm(String name) {
    return 'Delete workspace \"$name\"? This removes all members.';
  }

  @override
  String workspacesCreated(String name) {
    return 'Created workspace \"$name\".';
  }

  @override
  String workspacesLeft(String name) {
    return 'Left workspace \"$name\".';
  }

  @override
  String workspacesDeleted(String name) {
    return 'Deleted workspace \"$name\".';
  }

  @override
  String get workspacesJoined => 'Joined workspace.';

  @override
  String get workspacesCancel => 'Cancel';

  @override
  String get workspacesCreateTitle => 'New Workspace';

  @override
  String get workspacesCreateNameLabel => 'Workspace name';

  @override
  String get workspacesCreateNameHint => 'e.g. Data Platform Team';

  @override
  String get workspacesCreateRequired => 'Name is required.';

  @override
  String get workspacesCreateTooLong => 'Name must be 100 characters or fewer.';

  @override
  String get workspacesCreateButton => 'Create';

  @override
  String get workspacesJoinTitle => 'Join Workspace';

  @override
  String get workspacesJoinIdLabel => 'Workspace ID';

  @override
  String get workspacesJoinIdHint =>
      'Paste the workspace ID shared by an admin';

  @override
  String get workspacesJoinCodeLabel => 'Invite code';

  @override
  String get workspacesJoinCodeHint => '6-character code';

  @override
  String get workspacesJoinRequired => 'Both fields are required.';

  @override
  String get workspacesJoinHint =>
      'Ask a workspace admin for the Workspace ID and invite code, then paste both above.';

  @override
  String get workspacesJoinButton => 'Join';

  @override
  String workspacesMembersTitle(String name) {
    return 'Members — $name';
  }

  @override
  String get workspacesInviteCode => 'Invite code';

  @override
  String get workspacesCopyInvite => 'Copy invite';

  @override
  String get workspacesInviteCopied =>
      'Workspace ID + invite code copied to share.';

  @override
  String get workspacesMembersEmpty => 'No members.';

  @override
  String get workspacesRemoveMember => 'Remove';

  @override
  String workspacesRemoveMemberConfirm(String name) {
    return 'Remove $name from this workspace?';
  }

  @override
  String get workspacesYou => '(you)';

  @override
  String get layoutInsufficientSpace =>
      'Not enough space to expand this panel — enlarge the window';

  @override
  String get welcomeSubtitle => 'AI-enhanced database management';

  @override
  String get mcpTokensMenuLabel => 'MCP Tokens';

  @override
  String get mcpTokensTitle => 'MCP Tokens';

  @override
  String get mcpTokensIntro =>
      'Long-lived tokens for AI clients (Claude Code, Cursor). Paste one as the Bearer token in the client\'s MCP config; revoke any time.';

  @override
  String get mcpTokensNotConnected =>
      'Connect to a DbMaster server to manage MCP tokens.';

  @override
  String get mcpTokensEmpty => 'No tokens yet. Create one for your AI client.';

  @override
  String get mcpTokensNameHint => 'Token name (e.g. claude-code-mac)';

  @override
  String get mcpTokensCreate => 'Create';

  @override
  String mcpTokensOnceTitle(String name) {
    return 'Token \"$name\" created';
  }

  @override
  String get mcpTokensOnceWarning =>
      'Copy it now — for security it will never be shown again. Use it as the Bearer token in your MCP client config (e.g. mcp.json).';

  @override
  String get mcpTokensCopy => 'Copy';

  @override
  String get mcpTokensCopied => 'Token copied to clipboard';

  @override
  String get mcpTokensDone => 'Done';

  @override
  String mcpTokensLastUsed(String value) {
    return 'Last used: $value';
  }

  @override
  String get mcpTokensNeverUsed => 'never';

  @override
  String get mcpTokensRevoke => 'Revoke';

  @override
  String get mcpTokensRevokeTitle => 'Revoke this token?';

  @override
  String mcpTokensRevokeBody(String name, String prefix) {
    return 'Clients using \"$name\" ($prefix…) will stop working immediately. This cannot be undone.';
  }

  @override
  String get serverConnectionsMenuLabel => 'Server connections';

  @override
  String get serverConnectionsTitle => 'Server connections';

  @override
  String get serverConnectionsIntro =>
      'Connections registered on the server. Data sync, health checks and DDL approvals run against these; the desktop sidebar list is separate.';

  @override
  String get serverConnectionsNotConnected => 'Not connected to a server.';

  @override
  String get serverConnectionsEmpty =>
      'No server connections yet. Add one so data sync / health check / approval tasks have a database to run against.';

  @override
  String get serverConnectionsAdd => 'Add';

  @override
  String get serverConnectionsEdit => 'Edit';

  @override
  String get serverConnectionsDelete => 'Delete';

  @override
  String get serverConnectionsKindCollab => 'collab';

  @override
  String get serverConnectionsKindSourceDrift => 'drift source (read-only)';

  @override
  String get serverConnectionsDeleteTitle => 'Delete connection';

  @override
  String serverConnectionsDeleteBody(String name) {
    return 'Delete server connection \"$name\"?';
  }

  @override
  String serverConnectionsDeleteTaskWarning(num count) {
    return '$count task(s) reference this connection and will be deleted (as source) or detached (as target).';
  }

  @override
  String get serverConnFormCreateTitle => 'Add server connection';

  @override
  String get serverConnFormEditTitle => 'Edit server connection';

  @override
  String get serverConnFormName => 'Name';

  @override
  String get serverConnFormType => 'Type';

  @override
  String get serverConnFormHost => 'Host';

  @override
  String get serverConnFormPort => 'Port';

  @override
  String get serverConnFormUsername => 'Username';

  @override
  String get serverConnFormPassword => 'Password';

  @override
  String get serverConnFormPasswordKeepHint =>
      'Leave blank to keep the stored password';

  @override
  String get serverConnFormDatabase => 'Default database (optional)';

  @override
  String get serverConnFormSqlitePath => 'Database file path';

  @override
  String get serverConnFormSave => 'Save';

  @override
  String get serverConnFormRequired => 'Required';

  @override
  String get serverConnFormInvalidPort => 'Port must be a number';

  @override
  String get dataSyncConnectionNotOnServer =>
      'The selected connection is not registered on the server. Add it under \"Server connections\" first, then retry.';

  @override
  String get settingsLogs => 'Logs';

  @override
  String get logsUnavailable => 'Logging unavailable';

  @override
  String get logsOpenFolder => 'Open Folder';

  @override
  String get logsExport => 'Export';

  @override
  String get logsExportSuccess => 'Log exported';

  @override
  String logsExportFailed(String error) {
    return 'Export failed: $error';
  }

  @override
  String get logsOpenFolderFailed => 'Failed to open folder';

  @override
  String get updateSectionTitle => 'Updates';

  @override
  String get updateCheckButton => 'Check';

  @override
  String get updateGoDownload => 'Download';

  @override
  String get updateStatusChecking => 'Checking…';

  @override
  String get updateStatusUpToDate => 'You\'re up to date';

  @override
  String updateStatusAvailable(String version) {
    return 'New version available: $version';
  }

  @override
  String get updateStatusUnknownVersion =>
      'Current version unknown (development build)';

  @override
  String updateStatusUnknownLatest(String version) {
    return 'Latest release: $version (current version unknown)';
  }

  @override
  String get updateStatusFailed => 'Check failed — try again later';

  @override
  String updateCurrentVersion(String version) {
    return 'Current version: $version';
  }

  @override
  String get updateAutoCheck => 'Check for updates on startup';

  @override
  String get updateAutoCheckDesc =>
      'Silent check (at most once every 24h) against GitHub Releases';

  @override
  String serverVersionLine(String version) {
    return 'Server version: $version';
  }

  @override
  String serverVersionOutdated(String version, String min) {
    return 'Server $version is below the minimum compatible $min — please upgrade dbmaster-server';
  }

  @override
  String updateAvailableSnackbar(String version) {
    return 'New version $version is available';
  }

  @override
  String crashRestoredTabs(int count) {
    return 'The app exited unexpectedly last time — recovered $count tab(s)';
  }

  @override
  String get saveQueryNoConnection => 'Cannot save — no database connection';

  @override
  String get saveQueryReadOnly => 'Cannot save — this connection is read-only';

  @override
  String saveQueryFailed(String error) {
    return 'Save failed: $error';
  }

  @override
  String get editorSuggestionApplied => '✓ Suggestion applied — SQL updated';

  @override
  String get editorRestoreOriginalSql => 'Restore original SQL';

  @override
  String get editorIndexDdlFilled =>
      '✓ Index DDL inserted — press Run to execute (safety review will apply)';

  @override
  String get safetyReviewedLabel => 'Reviewed';

  @override
  String get statusConnecting => 'Connecting…';

  @override
  String get resultsContextCopyCell => 'Copy Cell';

  @override
  String get resultsContextCopyRowJson => 'Copy Row (JSON)';

  @override
  String get resultsContextExportRowInsert => 'Export Row as SQL INSERT';

  @override
  String get resultsContextExportAllInsert => 'Export All as SQL INSERT';

  @override
  String get resultsExtractNoKeys => 'No top-level keys found';

  @override
  String resultsExtractFieldTitle(String column) {
    return 'Extract field from \"$column\"';
  }

  @override
  String resultsCopiedExpression(String expression) {
    return 'Copied: $expression';
  }

  @override
  String get resultsExtractInvalidJson => 'Invalid JSON';

  @override
  String get resultsInsertNoTableName =>
      'Cannot determine table name from query';

  @override
  String get resultsInsertRowDone => 'Row exported as SQL INSERT to clipboard';

  @override
  String get resultsInsertNoData => 'No data to export';

  @override
  String resultsInsertAllDone(int count) {
    return '$count rows exported as SQL INSERT to clipboard';
  }

  @override
  String connectionFailedWith(String error) {
    return 'Connection failed: $error';
  }

  @override
  String get viewTableDdl => 'View DDL';

  @override
  String aboutVersionLine(String version) {
    return 'Version $version';
  }

  @override
  String get aboutFeedback => 'Feedback';

  @override
  String get driftHistoryBaseline => 'Baseline established';

  @override
  String get driftDiffOnlyBaseline =>
      'Only the baseline snapshot exists so far — the next run will diff against it. Drift detection starts from the second snapshot.';

  @override
  String mcpTokensCreatedAt(String time) {
    return 'Created $time';
  }

  @override
  String get mcpTokensEndpointHint =>
      'Configure this endpoint URL + the token (Bearer) in your MCP client (e.g. mcp.json):';

  @override
  String get mcpTokensEndpointCopied => 'Endpoint copied';

  @override
  String get historyLoadMore => 'Load more';

  @override
  String connectionFormProvidedBy(String plugin) {
    return 'Provided by $plugin';
  }

  @override
  String get connectionDbIndex => 'Database Index';

  @override
  String get connectionAuthDatabase => 'Authentication Database';

  @override
  String get connectionRedisAuthNone => 'No Auth';

  @override
  String get connectionRedisAuthNoneDesc => 'No authentication required';

  @override
  String get connectionRedisAuthPasswordOnly => 'Password Only';

  @override
  String get connectionRedisAuthPasswordOnlyDesc =>
      'AUTH password (Redis < 6.0)';

  @override
  String get connectionRedisAuthUsernamePassword => 'Username + Password (ACL)';

  @override
  String get connectionRedisAuthUsernamePasswordDesc =>
      'AUTH username password (Redis 6.0+ ACL)';

  @override
  String get connectionSshAuthPassword => 'Password';

  @override
  String get connectionSshAuthPrivateKey => 'Private Key';

  @override
  String get sidebarCapabilityTitle => 'Capabilities';

  @override
  String get sidebarCapGroupDatabaseObjects => 'Database Objects';

  @override
  String get sidebarCapGroupAdvanced => 'Advanced';

  @override
  String get redisCapGroupKeyspace => 'Keyspace';

  @override
  String get redisCapWorkbench => 'Command Line Workbench';

  @override
  String get redisCapPubsub => 'Pub/Sub';

  @override
  String get redisCapLua => 'Lua Scripts';

  @override
  String get redisCapPipeline => 'Pipeline';

  @override
  String get redisCapTransaction => 'Transaction';

  @override
  String get redisCapMemoryAnalysis => 'Memory Analysis';

  @override
  String get redisCapKeyspaceNotifications => 'Keyspace Notifications';

  @override
  String get redisCapAcl => 'ACL Management';

  @override
  String get redisCapConfig => 'Edit Config';

  @override
  String get mongoValidationTitle => 'Validation Rules';

  @override
  String get mongoValidationNoValidator =>
      'This collection has no validation rules configured (add via collMod or the MongoDB shell).';

  @override
  String mongoValidationLoadFailed(String error) {
    return 'Failed to load validation rules: $error';
  }

  @override
  String sidebarDocumentInserted(String collection) {
    return 'Document inserted into $collection';
  }

  @override
  String get aiSkillCatalogTitle => 'Skills';

  @override
  String get aiSkillGroupSql => 'SQL';

  @override
  String get aiSkillGroupData => 'Data';

  @override
  String get aiSkillGroupSchema => 'Schema';

  @override
  String get aiSkillGroupOps => 'Ops';

  @override
  String get aiSkillNl2sqlName => 'Natural Language to SQL';

  @override
  String get aiSkillNl2sqlDesc => 'Describe what you want and get SQL';

  @override
  String get aiSkillSqlExplainName => 'SQL Explain';

  @override
  String get aiSkillSqlExplainDesc => 'Walk through what a SQL statement does';

  @override
  String get aiSkillSqlExplainPrompt =>
      'Explain what this SQL statement does, step by step:\n```\n\n```';

  @override
  String get aiSkillQueryOptimizerName => 'Query Optimizer';

  @override
  String get aiSkillQueryOptimizerDesc =>
      'Analyze a slow query and suggest optimizations';

  @override
  String get aiSkillQueryOptimizerPrompt =>
      'Analyze this query for performance issues and suggest optimizations:\n```\n\n```';

  @override
  String get aiSkillDataCleaningName => 'Data Cleaning Advice';

  @override
  String get aiSkillDataCleaningDesc =>
      'Suggest how to clean up dirty data in a table';

  @override
  String get aiSkillDataCleaningPrompt =>
      'Suggest cleaning steps for dirty data in my table. Known issues:';

  @override
  String get aiSkillImportMappingName => 'Import Mapping';

  @override
  String get aiSkillImportMappingDesc =>
      'Generate a column mapping for data import';

  @override
  String get aiSkillImportMappingPrompt =>
      'Generate a column mapping (JSON) to import the following file into the table.\nSource columns:\nTarget columns:';

  @override
  String get aiSkillSchemaAnalysisName => 'Schema Analysis';

  @override
  String get aiSkillSchemaAnalysisDesc =>
      'Review the current schema and point out risks';

  @override
  String get aiSkillSchemaAnalysisPrompt =>
      'Review the current database schema and point out design risks and improvements.';

  @override
  String get aiSkillSchemaDiffName => 'Schema Diff Helper';

  @override
  String get aiSkillSchemaDiffDesc =>
      'Compare two schema definitions and output a diff';

  @override
  String get aiSkillSchemaDiffPrompt =>
      'Compare the following two schema definitions and output a unified diff:\n<schema-a>\n\n</schema-a>\n<schema-b>\n\n</schema-b>';

  @override
  String get aiSkillIndexSuggestName => 'Index Advice';

  @override
  String get aiSkillIndexSuggestDesc => 'Suggest indexes for a query or table';

  @override
  String get aiSkillIndexSuggestPrompt =>
      'Suggest indexes for this query and explain why:\n```\n\n```';

  @override
  String get aiSkillErrorDiagnosisName => 'Error Diagnosis';

  @override
  String get aiSkillErrorDiagnosisDesc => 'Diagnose a database error message';

  @override
  String get aiSkillErrorDiagnosisPrompt =>
      'Diagnose this database error and suggest fixes:\n```\n\n```';

  @override
  String get aiSkillSlowQueryName => 'Slow Query Analysis';

  @override
  String get aiSkillSlowQueryDesc => 'Analyze slow query log entries';

  @override
  String get aiSkillSlowQueryPrompt =>
      'Analyze this slow query log entry and locate the bottleneck:\n```\n\n```';

  @override
  String get aiContextPanelTitle => 'Context';

  @override
  String get aiContextConnectionSection => 'Current Connection';

  @override
  String get aiContextDatabaseSection => 'Current Database';

  @override
  String get aiContextNoConnection => 'No connection selected';

  @override
  String get aiContextSchemaContext => 'Include schema context';

  @override
  String get aiContextSchemaContextDesc =>
      'Attach table schemas of the current database when sending';

  @override
  String get aiPanelOpenSkillCatalog => 'Skill catalog';

  @override
  String get aiPanelOpenContextPanel => 'Context panel';

  @override
  String get safetyBannerAddLimit => 'Add LIMIT';

  @override
  String safetyBannerCooldown(int seconds) {
    return 'Confirm (${seconds}s)';
  }

  @override
  String get safetyDmlAllRowsWarning =>
      'This operation will affect all matching rows. Consider adding a LIMIT clause.';

  @override
  String get safetySeverityHigh => 'High';

  @override
  String get safetySeverityMedium => 'Warning';

  @override
  String get safetySeverityLow => 'Info';

  @override
  String get safetySeverityPolicy => 'Policy';

  @override
  String gateTitleSingle(int count) {
    return 'Execution check: $count risk(s) found in this SQL';
  }

  @override
  String gateTitleMulti(int count, int total) {
    return 'Execution check: $count risk(s) found across $total statements';
  }

  @override
  String get gateDdlImpactTitle => 'DDL impact analysis';

  @override
  String gateStatementLabel(int n) {
    return 'Stmt $n';
  }

  @override
  String get gateSuggestionLabel => 'Suggested fix';

  @override
  String gateOverview(int total, int high, int medium, int low, int ok) {
    return 'Statements $total · High $high · Warning $medium · Info $low · Clean $ok';
  }

  @override
  String gateSkipHighRisk(int skip, int exec) {
    return 'Skip $skip high-risk, run $exec';
  }

  @override
  String get gateAllHighDisabled => 'All high-risk — nothing to run';

  @override
  String get gateApplySuggestions => 'Apply suggestions';

  @override
  String get gateProceed => 'Run anyway';

  @override
  String get gateProceedAll => 'Run all anyway';

  @override
  String get gateCancelAll => 'Cancel all';

  @override
  String get settingsNavAppearance => 'Appearance';

  @override
  String get settingsNavAi => 'AI';

  @override
  String get settingsNavQuery => 'Query';

  @override
  String get settingsNavLanguage => 'Language';

  @override
  String get settingsNavSecurity => 'Security';

  @override
  String get settingsNavAbout => 'About';

  @override
  String get piiExportStepFormat => 'Format';

  @override
  String get piiExportStepScan => 'PII Scan';

  @override
  String get piiExportStepConfirm => 'Confirm';

  @override
  String get piiExportNoPiiTitle => 'No PII detected';

  @override
  String get piiExportNoPiiSubtitle => 'All columns will be exported as-is';

  @override
  String piiExportDetectedCount(int count) {
    return '$count columns contain PII';
  }

  @override
  String get piiExportHighSensitivity => '(high sensitivity)';

  @override
  String get piiExportKeep => 'Keep';

  @override
  String get piiExportMask => 'Mask';

  @override
  String get piiExportHash => 'Hash';

  @override
  String get piiExportDrop => 'Drop column';

  @override
  String get piiExportReadyTitle => 'Ready to export';

  @override
  String get piiExportSummaryFormat => 'Format';

  @override
  String get piiExportSummaryRows => 'Rows';

  @override
  String get piiExportSummaryPiiColumns => 'PII columns handled';

  @override
  String get piiExportFootnote =>
      'PII columns follow the chosen actions; non-PII columns export as-is';

  @override
  String get serverBarNotConnected => 'Not connected';

  @override
  String get serverBarConnecting => 'Connecting…';

  @override
  String get serverBarLocal => 'Local';

  @override
  String get serverBarConnected => 'Connected';

  @override
  String get serverBarReconnecting => 'Reconnecting…';

  @override
  String serverBarReconnectingIn(int seconds) {
    return 'Reconnecting in ${seconds}s…';
  }

  @override
  String serverBarServerUrl(String url) {
    return 'Server: $url';
  }

  @override
  String get serverBarDisconnect => 'Disconnect';

  @override
  String get serverBarUnknownUser => 'Unknown';

  @override
  String get serverConnectUnexpectedError => 'An unexpected error occurred.';

  @override
  String get cellViewerCopy => 'Copy';

  @override
  String cellViewerChars(Object count) {
    return '$count characters';
  }

  @override
  String get slowQueryMenuLabel => 'Slow Query Stats';

  @override
  String get slowQueryDialogTitle => 'Slow Query Stats';

  @override
  String slowQueryScopeBanner(int thresholdMs) {
    return 'Queries run through dbmaster/server slower than $thresholdMs ms are recorded; when native slow-log collection is enabled on the instance, the database\'s own slow queries are included too (distinguished by source).';
  }

  @override
  String get slowQueryWindow1h => 'Last hour';

  @override
  String get slowQueryWindow24h => 'Last 24 hours';

  @override
  String get slowQueryWindow7d => 'Last 7 days';

  @override
  String get slowQuerySortTotalMs => 'Total time';

  @override
  String get slowQuerySortCount => 'Count';

  @override
  String get slowQuerySortAvgMs => 'Avg time';

  @override
  String get slowQuerySortMaxMs => 'Max time';

  @override
  String get slowQueryAllConnections => 'All connections';

  @override
  String slowQueryDigestStats(int count, String total, String avg, String max) {
    return '$count calls · total $total · avg $avg · max $max';
  }

  @override
  String slowQueryLastSeen(String time) {
    return 'last seen $time';
  }

  @override
  String get slowQueryEmptyTitle => 'No slow queries';

  @override
  String get slowQueryEmptyBody =>
      'Nothing above the sampling threshold in this window. Run something slow through dbmaster and come back.';

  @override
  String get slowQueryLoadFailed => 'Failed to load slow query stats.';

  @override
  String get slowQueryRetry => 'Retry';

  @override
  String slowQueryLoadMore(int shown, int total) {
    return 'Show more ($shown of $total)';
  }

  @override
  String get slowQueryStatusOk => 'ok';

  @override
  String get slowQueryStatusError => 'error';

  @override
  String get slowQueryStatusCancelled => 'cancelled';

  @override
  String get slowQueryDatabaseLabel => 'Database';

  @override
  String get slowQueryNoPlaintext =>
      'Plaintext SQL is disabled on this instance (digest only).';

  @override
  String get slowQueryCopySql => 'Copy SQL';

  @override
  String get slowQueryCopied => 'Copied';

  @override
  String get reportsMenuLabel => 'Reports';

  @override
  String get reportsDialogTitle => 'Reports';

  @override
  String get reportsGenerateButton => 'Generate weekly report';

  @override
  String get reportsGeneratedToast => 'Weekly report generated.';

  @override
  String get reportsExistingToast => 'This week\'s report already exists.';

  @override
  String get reportsEmptyTitle => 'No reports';

  @override
  String get reportsEmptyBody =>
      'Generate this week\'s slow-query report, or wait for the weekly schedule.';

  @override
  String get reportsLoadFailed => 'Failed to load reports.';

  @override
  String get reportsRetry => 'Retry';

  @override
  String reportsLoadMore(int shown, int total) {
    return 'Show more ($shown of $total)';
  }

  @override
  String get reportsWindowLabel => 'Window';

  @override
  String get reportsTruncatedHint =>
      'Partial window: older samples were already rotated out by retention.';

  @override
  String get reportsSamplesLabel => 'Samples';

  @override
  String get reportsDistinctLabel => 'Distinct queries';

  @override
  String get reportsTotalTimeLabel => 'Total time';

  @override
  String get reportsErrorsLabel => 'Errors';

  @override
  String get reportsWowLabel => 'vs last week';

  @override
  String get reportsTopSection => 'Top queries';

  @override
  String get reportsByDaySection => 'By day';

  @override
  String get reportsByConnectionSection => 'By connection';

  @override
  String get reportsUnknownType => 'Unknown report type — raw content:';

  @override
  String get reportsAnalyzeWithAi => 'Analyze with AI';
}
