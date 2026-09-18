import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_de.dart';
import 'app_localizations_en.dart';
import 'app_localizations_fr.dart';
import 'app_localizations_ru.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('de'),
    Locale('en'),
    Locale('fr'),
    Locale('ru'),
    Locale('zh'),
    Locale('zh', 'TW'),
  ];

  /// No description provided for @filterBarApply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get filterBarApply;

  /// No description provided for @filterBarAddCondition.
  ///
  /// In en, this message translates to:
  /// **'Add condition'**
  String get filterBarAddCondition;

  /// No description provided for @filterBarAnd.
  ///
  /// In en, this message translates to:
  /// **'AND'**
  String get filterBarAnd;

  /// No description provided for @filterBarOr.
  ///
  /// In en, this message translates to:
  /// **'OR'**
  String get filterBarOr;

  /// No description provided for @filterBarNoColumns.
  ///
  /// In en, this message translates to:
  /// **'No columns'**
  String get filterBarNoColumns;

  /// No description provided for @filterBarLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get filterBarLoading;

  /// No description provided for @mongoAutocompleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Mongo Autocomplete'**
  String get mongoAutocompleteTitle;

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'DbMaster'**
  String get appTitle;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// No description provided for @settingsTheme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get settingsTheme;

  /// No description provided for @settingsGeneral.
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get settingsGeneral;

  /// No description provided for @settingsConnection.
  ///
  /// In en, this message translates to:
  /// **'Connection'**
  String get settingsConnection;

  /// No description provided for @settingsEditor.
  ///
  /// In en, this message translates to:
  /// **'Editor'**
  String get settingsEditor;

  /// No description provided for @settingsAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsAbout;

  /// No description provided for @connectionNewConnection.
  ///
  /// In en, this message translates to:
  /// **'New Connection'**
  String get connectionNewConnection;

  /// No description provided for @connectionEditConnection.
  ///
  /// In en, this message translates to:
  /// **'Edit Connection'**
  String get connectionEditConnection;

  /// No description provided for @connectionManageConnection.
  ///
  /// In en, this message translates to:
  /// **'Manage Connection'**
  String get connectionManageConnection;

  /// No description provided for @connectionDeleteConnection.
  ///
  /// In en, this message translates to:
  /// **'Delete Connection'**
  String get connectionDeleteConnection;

  /// No description provided for @connectionConnect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get connectionConnect;

  /// No description provided for @connectionCreateDatabase.
  ///
  /// In en, this message translates to:
  /// **'Create Database'**
  String get connectionCreateDatabase;

  /// No description provided for @connectionEnableReadOnly.
  ///
  /// In en, this message translates to:
  /// **'Enable Read-Only'**
  String get connectionEnableReadOnly;

  /// No description provided for @connectionDisableReadOnly.
  ///
  /// In en, this message translates to:
  /// **'Disable Read-Only'**
  String get connectionDisableReadOnly;

  /// No description provided for @connectionMoveToGroup.
  ///
  /// In en, this message translates to:
  /// **'Move to {groupName}'**
  String connectionMoveToGroup(String groupName);

  /// No description provided for @connectionRemoveFromGroup.
  ///
  /// In en, this message translates to:
  /// **'Remove from Group'**
  String get connectionRemoveFromGroup;

  /// No description provided for @connectionCollapseAll.
  ///
  /// In en, this message translates to:
  /// **'Collapse All'**
  String get connectionCollapseAll;

  /// No description provided for @connectionDisconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get connectionDisconnect;

  /// No description provided for @connectionTestConnection.
  ///
  /// In en, this message translates to:
  /// **'Test Connection'**
  String get connectionTestConnection;

  /// No description provided for @connectionConnectionName.
  ///
  /// In en, this message translates to:
  /// **'Connection Name'**
  String get connectionConnectionName;

  /// No description provided for @connectionHost.
  ///
  /// In en, this message translates to:
  /// **'Host'**
  String get connectionHost;

  /// No description provided for @connectionPort.
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get connectionPort;

  /// No description provided for @connectionUsername.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get connectionUsername;

  /// No description provided for @connectionPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get connectionPassword;

  /// No description provided for @connectionDatabase.
  ///
  /// In en, this message translates to:
  /// **'Database'**
  String get connectionDatabase;

  /// No description provided for @connectionEnvironment.
  ///
  /// In en, this message translates to:
  /// **'Environment'**
  String get connectionEnvironment;

  /// No description provided for @connectionEnvironmentNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get connectionEnvironmentNone;

  /// No description provided for @commonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get commonDelete;

  /// No description provided for @commonEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get commonEdit;

  /// No description provided for @commonAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get commonAdd;

  /// No description provided for @commonClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

  /// No description provided for @commonDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get commonDone;

  /// No description provided for @commonSelect.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get commonSelect;

  /// No description provided for @commonConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get commonConfirm;

  /// No description provided for @commonSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get commonSearch;

  /// No description provided for @commonRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get commonRefresh;

  /// No description provided for @commonLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get commonLoading;

  /// No description provided for @commonNoData.
  ///
  /// In en, this message translates to:
  /// **'No Data'**
  String get commonNoData;

  /// No description provided for @commonSuccess.
  ///
  /// In en, this message translates to:
  /// **'Success'**
  String get commonSuccess;

  /// No description provided for @commonError.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get commonError;

  /// No description provided for @commonWarning.
  ///
  /// In en, this message translates to:
  /// **'Warning'**
  String get commonWarning;

  /// No description provided for @tableNewTable.
  ///
  /// In en, this message translates to:
  /// **'ER Diagram'**
  String get tableNewTable;

  /// No description provided for @tableEditTable.
  ///
  /// In en, this message translates to:
  /// **'Edit Table'**
  String get tableEditTable;

  /// No description provided for @tableDeleteTable.
  ///
  /// In en, this message translates to:
  /// **'Delete Table'**
  String get tableDeleteTable;

  /// No description provided for @tableTableName.
  ///
  /// In en, this message translates to:
  /// **'Table Name'**
  String get tableTableName;

  /// No description provided for @tableColumns.
  ///
  /// In en, this message translates to:
  /// **'Columns'**
  String get tableColumns;

  /// No description provided for @tableIndexes.
  ///
  /// In en, this message translates to:
  /// **'Indexes'**
  String get tableIndexes;

  /// No description provided for @tablePrimaryKey.
  ///
  /// In en, this message translates to:
  /// **'Primary Key'**
  String get tablePrimaryKey;

  /// No description provided for @tableForeignKey.
  ///
  /// In en, this message translates to:
  /// **'Foreign Key'**
  String get tableForeignKey;

  /// No description provided for @tableRenameTable.
  ///
  /// In en, this message translates to:
  /// **'Rename Table'**
  String get tableRenameTable;

  /// No description provided for @tableNewTableName.
  ///
  /// In en, this message translates to:
  /// **'New table name'**
  String get tableNewTableName;

  /// No description provided for @queryExecute.
  ///
  /// In en, this message translates to:
  /// **'Execute'**
  String get queryExecute;

  /// No description provided for @queryExecuteSelected.
  ///
  /// In en, this message translates to:
  /// **'Execute Selected'**
  String get queryExecuteSelected;

  /// No description provided for @queryFormat.
  ///
  /// In en, this message translates to:
  /// **'Format'**
  String get queryFormat;

  /// No description provided for @queryClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get queryClear;

  /// No description provided for @queryHistory.
  ///
  /// In en, this message translates to:
  /// **'Query History'**
  String get queryHistory;

  /// No description provided for @queryResults.
  ///
  /// In en, this message translates to:
  /// **'Results'**
  String get queryResults;

  /// No description provided for @sidebarConnections.
  ///
  /// In en, this message translates to:
  /// **'Connections'**
  String get sidebarConnections;

  /// No description provided for @sidebarDatabases.
  ///
  /// In en, this message translates to:
  /// **'Databases'**
  String get sidebarDatabases;

  /// No description provided for @sidebarTables.
  ///
  /// In en, this message translates to:
  /// **'Tables'**
  String get sidebarTables;

  /// No description provided for @sidebarKeys.
  ///
  /// In en, this message translates to:
  /// **'Keys'**
  String get sidebarKeys;

  /// No description provided for @sidebarCollections.
  ///
  /// In en, this message translates to:
  /// **'Collections'**
  String get sidebarCollections;

  /// No description provided for @sidebarSuperTables.
  ///
  /// In en, this message translates to:
  /// **'SuperTables'**
  String get sidebarSuperTables;

  /// No description provided for @sidebarViews.
  ///
  /// In en, this message translates to:
  /// **'Views'**
  String get sidebarViews;

  /// No description provided for @sidebarSavedQueries.
  ///
  /// In en, this message translates to:
  /// **'Saved Queries'**
  String get sidebarSavedQueries;

  /// No description provided for @sidebarProcedures.
  ///
  /// In en, this message translates to:
  /// **'Stored Procedures'**
  String get sidebarProcedures;

  /// No description provided for @sidebarTriggers.
  ///
  /// In en, this message translates to:
  /// **'Triggers'**
  String get sidebarTriggers;

  /// No description provided for @sidebarFunctions.
  ///
  /// In en, this message translates to:
  /// **'Functions'**
  String get sidebarFunctions;

  /// No description provided for @sidebarServer.
  ///
  /// In en, this message translates to:
  /// **'Server'**
  String get sidebarServer;

  /// No description provided for @sidebarProcessList.
  ///
  /// In en, this message translates to:
  /// **'Process List'**
  String get sidebarProcessList;

  /// No description provided for @sidebarServerStatus.
  ///
  /// In en, this message translates to:
  /// **'Server Status'**
  String get sidebarServerStatus;

  /// No description provided for @sidebarNoUsers.
  ///
  /// In en, this message translates to:
  /// **'No users'**
  String get sidebarNoUsers;

  /// No description provided for @sidebarNoActiveProcesses.
  ///
  /// In en, this message translates to:
  /// **'No active processes'**
  String get sidebarNoActiveProcesses;

  /// No description provided for @sidebarTdColsTags.
  ///
  /// In en, this message translates to:
  /// **'{cols} cols, {tags} tags'**
  String sidebarTdColsTags(int cols, int tags);

  /// No description provided for @sidebarTdColumnsCount.
  ///
  /// In en, this message translates to:
  /// **'Columns ({count})'**
  String sidebarTdColumnsCount(int count);

  /// No description provided for @sidebarTdTagsCount.
  ///
  /// In en, this message translates to:
  /// **'Tags ({count})'**
  String sidebarTdTagsCount(int count);

  /// No description provided for @sidebarTdDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete SuperTable'**
  String get sidebarTdDeleteTitle;

  /// No description provided for @sidebarTdDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete SuperTable \"{name}\"?\n\nThis will also delete all its SubTables!'**
  String sidebarTdDeleteConfirm(String name);

  /// No description provided for @sidebarDeleteGroup.
  ///
  /// In en, this message translates to:
  /// **'Delete Group'**
  String get sidebarDeleteGroup;

  /// No description provided for @sidebarDeleteGroupPrompt.
  ///
  /// In en, this message translates to:
  /// **'Select a group to delete:'**
  String get sidebarDeleteGroupPrompt;

  /// No description provided for @sidebarConnectionSwitch.
  ///
  /// In en, this message translates to:
  /// **'Switch connection'**
  String get sidebarConnectionSwitch;

  /// No description provided for @sidebarSelectConnectionHint.
  ///
  /// In en, this message translates to:
  /// **'Select a connection from the picker above to start'**
  String get sidebarSelectConnectionHint;

  /// No description provided for @sidebarConnectionNone.
  ///
  /// In en, this message translates to:
  /// **'No connection'**
  String get sidebarConnectionNone;

  /// No description provided for @sidebarManageConnections.
  ///
  /// In en, this message translates to:
  /// **'Manage Connections…'**
  String get sidebarManageConnections;

  /// No description provided for @sidebarExtensions.
  ///
  /// In en, this message translates to:
  /// **'Extensions'**
  String get sidebarExtensions;

  /// No description provided for @noExtensionsInstalled.
  ///
  /// In en, this message translates to:
  /// **'No extensions installed'**
  String get noExtensionsInstalled;

  /// No description provided for @sidebarSchemas.
  ///
  /// In en, this message translates to:
  /// **'Schemas'**
  String get sidebarSchemas;

  /// No description provided for @sidebarMaterializedViews.
  ///
  /// In en, this message translates to:
  /// **'Materialized Views'**
  String get sidebarMaterializedViews;

  /// No description provided for @sidebarSequences.
  ///
  /// In en, this message translates to:
  /// **'Sequences'**
  String get sidebarSequences;

  /// No description provided for @settingsGeneralSettings.
  ///
  /// In en, this message translates to:
  /// **'General Settings'**
  String get settingsGeneralSettings;

  /// No description provided for @settingsAppearanceSettings.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsAppearanceSettings;

  /// No description provided for @settingsEditorSettings.
  ///
  /// In en, this message translates to:
  /// **'Editor Settings'**
  String get settingsEditorSettings;

  /// No description provided for @settingsEnableAutocomplete.
  ///
  /// In en, this message translates to:
  /// **'Enable Autocomplete'**
  String get settingsEnableAutocomplete;

  /// No description provided for @settingsAutocompleteDescription.
  ///
  /// In en, this message translates to:
  /// **'Automatically suggest SQL keywords and table names'**
  String get settingsAutocompleteDescription;

  /// No description provided for @settingsSqlCoolTheme.
  ///
  /// In en, this message translates to:
  /// **'SQL Cool Theme'**
  String get settingsSqlCoolTheme;

  /// No description provided for @settingsSqlCoolThemeDesc.
  ///
  /// In en, this message translates to:
  /// **'Use the cool syntax palette (matches the app shell). Turn off for the platform default palette.'**
  String get settingsSqlCoolThemeDesc;

  /// No description provided for @safetyRulesSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Safety Rules'**
  String get safetyRulesSectionTitle;

  /// No description provided for @safetyRuleSchemaCompat.
  ///
  /// In en, this message translates to:
  /// **'Schema Compatibility'**
  String get safetyRuleSchemaCompat;

  /// No description provided for @safetyRuleSchemaCompatDesc.
  ///
  /// In en, this message translates to:
  /// **'Check referenced columns exist in the table before execution'**
  String get safetyRuleSchemaCompatDesc;

  /// No description provided for @safetyRuleMissingLimit.
  ///
  /// In en, this message translates to:
  /// **'Missing LIMIT Warning'**
  String get safetyRuleMissingLimit;

  /// No description provided for @safetyRuleMissingLimitDesc.
  ///
  /// In en, this message translates to:
  /// **'Warn when querying large tables without a LIMIT clause'**
  String get safetyRuleMissingLimitDesc;

  /// No description provided for @safetyRuleFullTableScan.
  ///
  /// In en, this message translates to:
  /// **'Full Table Scan (Static)'**
  String get safetyRuleFullTableScan;

  /// No description provided for @safetyRuleFullTableScanDesc.
  ///
  /// In en, this message translates to:
  /// **'Detect index-breaking patterns in WHERE clauses (e.g. function-wrapped columns)'**
  String get safetyRuleFullTableScanDesc;

  /// No description provided for @safetyRuleSqlInjection.
  ///
  /// In en, this message translates to:
  /// **'SQL Injection Detection'**
  String get safetyRuleSqlInjection;

  /// No description provided for @safetyRuleSqlInjectionDesc.
  ///
  /// In en, this message translates to:
  /// **'Flag common SQL injection patterns (tautologies, comment truncation)'**
  String get safetyRuleSqlInjectionDesc;

  /// No description provided for @safetyRuleExplainFullScan.
  ///
  /// In en, this message translates to:
  /// **'Full Table Scan (EXPLAIN)'**
  String get safetyRuleExplainFullScan;

  /// No description provided for @safetyRuleExplainFullScanDesc.
  ///
  /// In en, this message translates to:
  /// **'Run EXPLAIN to detect actual full table scans chosen by the optimizer'**
  String get safetyRuleExplainFullScanDesc;

  /// No description provided for @safetyRuleExplainEstimatedRows.
  ///
  /// In en, this message translates to:
  /// **'Large Result Set Warning (EXPLAIN)'**
  String get safetyRuleExplainEstimatedRows;

  /// No description provided for @safetyRuleExplainEstimatedRowsDesc.
  ///
  /// In en, this message translates to:
  /// **'Run EXPLAIN to warn when estimated returned rows exceed the threshold'**
  String get safetyRuleExplainEstimatedRowsDesc;

  /// No description provided for @safetyRuleExecutableComment.
  ///
  /// In en, this message translates to:
  /// **'MySQL Executable Comments'**
  String get safetyRuleExecutableComment;

  /// No description provided for @safetyRuleExecutableCommentDesc.
  ///
  /// In en, this message translates to:
  /// **'Detect statements hidden in /*! ... */ version comments (executed by MySQL)'**
  String get safetyRuleExecutableCommentDesc;

  /// No description provided for @safetyRuleTautologyPredicate.
  ///
  /// In en, this message translates to:
  /// **'Tautology Predicates'**
  String get safetyRuleTautologyPredicate;

  /// No description provided for @safetyRuleTautologyPredicateDesc.
  ///
  /// In en, this message translates to:
  /// **'Detect always-true WHERE conditions such as 1=1, TRUE, and self-comparisons'**
  String get safetyRuleTautologyPredicateDesc;

  /// No description provided for @safetyRuleComplementaryOr.
  ///
  /// In en, this message translates to:
  /// **'Complementary OR Branches'**
  String get safetyRuleComplementaryOr;

  /// No description provided for @safetyRuleComplementaryOrDesc.
  ///
  /// In en, this message translates to:
  /// **'Detect complementary always-true OR branches such as x IS NULL OR x IS NOT NULL'**
  String get safetyRuleComplementaryOrDesc;

  /// No description provided for @safetyRuleWritableCte.
  ///
  /// In en, this message translates to:
  /// **'Writable CTEs'**
  String get safetyRuleWritableCte;

  /// No description provided for @safetyRuleWritableCteDesc.
  ///
  /// In en, this message translates to:
  /// **'Detect DELETE/UPDATE/INSERT embedded in WITH clause CTE bodies'**
  String get safetyRuleWritableCteDesc;

  /// No description provided for @safetyRuleFileWrite.
  ///
  /// In en, this message translates to:
  /// **'Filesystem Access'**
  String get safetyRuleFileWrite;

  /// No description provided for @safetyRuleFileWriteDesc.
  ///
  /// In en, this message translates to:
  /// **'Detect INTO OUTFILE/DUMPFILE and LOAD_FILE server file access'**
  String get safetyRuleFileWriteDesc;

  /// No description provided for @safetyRuleReviewFailClosed.
  ///
  /// In en, this message translates to:
  /// **'Fail-Closed for Writes'**
  String get safetyRuleReviewFailClosed;

  /// No description provided for @safetyRuleReviewFailClosedDesc.
  ///
  /// In en, this message translates to:
  /// **'Warn on write statements when safety review degrades (reads pass through)'**
  String get safetyRuleReviewFailClosedDesc;

  /// No description provided for @safetyFullScanThreshold.
  ///
  /// In en, this message translates to:
  /// **'Row count threshold (missing LIMIT / full scan / large result)'**
  String get safetyFullScanThreshold;

  /// No description provided for @settingsAiSettings.
  ///
  /// In en, this message translates to:
  /// **'AI Settings'**
  String get settingsAiSettings;

  /// No description provided for @settingsAutoExecuteSql.
  ///
  /// In en, this message translates to:
  /// **'Auto Execute SQL'**
  String get settingsAutoExecuteSql;

  /// No description provided for @settingsAutoExecuteSqlDescription.
  ///
  /// In en, this message translates to:
  /// **'Automatically execute SQL when a tab is opened'**
  String get settingsAutoExecuteSqlDescription;

  /// No description provided for @settingsThemeSettings.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get settingsThemeSettings;

  /// No description provided for @settingsDarkMode.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsDarkMode;

  /// No description provided for @settingsLightMode.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsLightMode;

  /// No description provided for @shortcutCategoryFile.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get shortcutCategoryFile;

  /// No description provided for @shortcutCategoryEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get shortcutCategoryEdit;

  /// No description provided for @shortcutCategoryView.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get shortcutCategoryView;

  /// No description provided for @shortcutCategoryAi.
  ///
  /// In en, this message translates to:
  /// **'AI'**
  String get shortcutCategoryAi;

  /// No description provided for @shortcutCategoryTab.
  ///
  /// In en, this message translates to:
  /// **'Tabs'**
  String get shortcutCategoryTab;

  /// No description provided for @shortcutNewConnection.
  ///
  /// In en, this message translates to:
  /// **'New Connection'**
  String get shortcutNewConnection;

  /// No description provided for @shortcutNewTab.
  ///
  /// In en, this message translates to:
  /// **'New Tab'**
  String get shortcutNewTab;

  /// No description provided for @shortcutCloseTab.
  ///
  /// In en, this message translates to:
  /// **'Close Tab'**
  String get shortcutCloseTab;

  /// No description provided for @shortcutSaveQuery.
  ///
  /// In en, this message translates to:
  /// **'Save Query'**
  String get shortcutSaveQuery;

  /// No description provided for @shortcutExportData.
  ///
  /// In en, this message translates to:
  /// **'Export Data'**
  String get shortcutExportData;

  /// No description provided for @shortcutExecuteQuery.
  ///
  /// In en, this message translates to:
  /// **'Execute Query'**
  String get shortcutExecuteQuery;

  /// No description provided for @shortcutExecuteQueryNewTab.
  ///
  /// In en, this message translates to:
  /// **'Execute Query in New Tab'**
  String get shortcutExecuteQueryNewTab;

  /// No description provided for @shortcutFormatSql.
  ///
  /// In en, this message translates to:
  /// **'Format SQL'**
  String get shortcutFormatSql;

  /// No description provided for @shortcutFind.
  ///
  /// In en, this message translates to:
  /// **'Find'**
  String get shortcutFind;

  /// No description provided for @shortcutReplace.
  ///
  /// In en, this message translates to:
  /// **'Replace'**
  String get shortcutReplace;

  /// No description provided for @shortcutAutocomplete.
  ///
  /// In en, this message translates to:
  /// **'Autocomplete'**
  String get shortcutAutocomplete;

  /// No description provided for @shortcutUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get shortcutUndo;

  /// No description provided for @shortcutRedo.
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get shortcutRedo;

  /// No description provided for @shortcutToggleSidebar.
  ///
  /// In en, this message translates to:
  /// **'Toggle Sidebar'**
  String get shortcutToggleSidebar;

  /// No description provided for @shortcutToggleAiPanel.
  ///
  /// In en, this message translates to:
  /// **'Toggle AI Panel'**
  String get shortcutToggleAiPanel;

  /// No description provided for @shortcutCommandPalette.
  ///
  /// In en, this message translates to:
  /// **'Command Palette'**
  String get shortcutCommandPalette;

  /// No description provided for @shortcutShortcutHelp.
  ///
  /// In en, this message translates to:
  /// **'Keyboard Shortcuts'**
  String get shortcutShortcutHelp;

  /// No description provided for @shortcutGenerateSql.
  ///
  /// In en, this message translates to:
  /// **'Generate SQL'**
  String get shortcutGenerateSql;

  /// No description provided for @shortcutOptimizeSql.
  ///
  /// In en, this message translates to:
  /// **'Optimize SQL'**
  String get shortcutOptimizeSql;

  /// No description provided for @shortcutExplainSql.
  ///
  /// In en, this message translates to:
  /// **'Explain SQL'**
  String get shortcutExplainSql;

  /// No description provided for @shortcutNextTab.
  ///
  /// In en, this message translates to:
  /// **'Next Tab'**
  String get shortcutNextTab;

  /// No description provided for @shortcutPreviousTab.
  ///
  /// In en, this message translates to:
  /// **'Previous Tab'**
  String get shortcutPreviousTab;

  /// No description provided for @shortcutSwitchToTab.
  ///
  /// In en, this message translates to:
  /// **'Switch to Tab'**
  String get shortcutSwitchToTab;

  /// No description provided for @shortcutToggleAiFullscreen.
  ///
  /// In en, this message translates to:
  /// **'AI Panel Fullscreen'**
  String get shortcutToggleAiFullscreen;

  /// No description provided for @shortcutAuditLog.
  ///
  /// In en, this message translates to:
  /// **'Query Audit Log'**
  String get shortcutAuditLog;

  /// No description provided for @shortcutIncreaseOpacity.
  ///
  /// In en, this message translates to:
  /// **'Increase Overlay Opacity'**
  String get shortcutIncreaseOpacity;

  /// No description provided for @shortcutDecreaseOpacity.
  ///
  /// In en, this message translates to:
  /// **'Decrease Overlay Opacity'**
  String get shortcutDecreaseOpacity;

  /// No description provided for @tableCreateNewTable.
  ///
  /// In en, this message translates to:
  /// **'Create New Table'**
  String get tableCreateNewTable;

  /// No description provided for @toolbarBackup.
  ///
  /// In en, this message translates to:
  /// **'Backup'**
  String get toolbarBackup;

  /// No description provided for @toolbarImport.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get toolbarImport;

  /// No description provided for @toolbarExport.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get toolbarExport;

  /// Tooltip for expand button
  ///
  /// In en, this message translates to:
  /// **'Expand'**
  String get sidebarExpand;

  /// No description provided for @sidebarSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get sidebarSettings;

  /// No description provided for @sidebarSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search connections, tables, views...'**
  String get sidebarSearchHint;

  /// No description provided for @sidebarConnectionActive.
  ///
  /// In en, this message translates to:
  /// **'{count} connections active'**
  String sidebarConnectionActive(Object count);

  /// No description provided for @sidebarNoConnections.
  ///
  /// In en, this message translates to:
  /// **'No saved connections'**
  String get sidebarNoConnections;

  /// No description provided for @sidebarClickToCreateConnection.
  ///
  /// In en, this message translates to:
  /// **'Click the button below to create a connection'**
  String get sidebarClickToCreateConnection;

  /// No description provided for @sidebarCreateConnection.
  ///
  /// In en, this message translates to:
  /// **'Create Connection'**
  String get sidebarCreateConnection;

  /// No description provided for @resultsExport.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get resultsExport;

  /// No description provided for @resultsSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get resultsSave;

  /// No description provided for @resultsDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get resultsDiscard;

  /// No description provided for @resultsNoDataToExport.
  ///
  /// In en, this message translates to:
  /// **'No data to export'**
  String get resultsNoDataToExport;

  /// No description provided for @cellEditNotSupported.
  ///
  /// In en, this message translates to:
  /// **'Cell editing is not available yet — edits cannot be saved back to the database'**
  String get cellEditNotSupported;

  /// No description provided for @exportExcelGenerating.
  ///
  /// In en, this message translates to:
  /// **'Generating Excel…'**
  String get exportExcelGenerating;

  /// No description provided for @resultsCSV.
  ///
  /// In en, this message translates to:
  /// **'CSV'**
  String get resultsCSV;

  /// No description provided for @resultsJSON.
  ///
  /// In en, this message translates to:
  /// **'JSON'**
  String get resultsJSON;

  /// No description provided for @resultsExcel.
  ///
  /// In en, this message translates to:
  /// **'Excel'**
  String get resultsExcel;

  /// No description provided for @resultsConfirmDiscardChanges.
  ///
  /// In en, this message translates to:
  /// **'Confirm Discard Changes'**
  String get resultsConfirmDiscardChanges;

  /// No description provided for @resultsDiscardChangesMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to discard {count} changes? This action cannot be undone.'**
  String resultsDiscardChangesMessage(Object count);

  /// No description provided for @resultsContinueEditing.
  ///
  /// In en, this message translates to:
  /// **'Continue Editing'**
  String get resultsContinueEditing;

  /// No description provided for @resultsDiscardChanges.
  ///
  /// In en, this message translates to:
  /// **'Discard Changes'**
  String get resultsDiscardChanges;

  /// No description provided for @resultsConfirmExecuteSQL.
  ///
  /// In en, this message translates to:
  /// **'Confirm Execute SQL'**
  String get resultsConfirmExecuteSQL;

  /// No description provided for @resultsBarChart.
  ///
  /// In en, this message translates to:
  /// **'Bar Chart'**
  String get resultsBarChart;

  /// No description provided for @resultsLineChart.
  ///
  /// In en, this message translates to:
  /// **'Line Chart'**
  String get resultsLineChart;

  /// No description provided for @resultsPieChart.
  ///
  /// In en, this message translates to:
  /// **'Pie Chart'**
  String get resultsPieChart;

  /// No description provided for @resultsSelectAxisFields.
  ///
  /// In en, this message translates to:
  /// **'Please select X-axis and Y-axis fields'**
  String get resultsSelectAxisFields;

  /// No description provided for @statusNotConnected.
  ///
  /// In en, this message translates to:
  /// **'Not Connected'**
  String get statusNotConnected;

  /// No description provided for @statusConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get statusConnected;

  /// No description provided for @statusTables.
  ///
  /// In en, this message translates to:
  /// **'{count} Tables'**
  String statusTables(Object count);

  /// No description provided for @statusNone.
  ///
  /// In en, this message translates to:
  /// **'None'**
  String get statusNone;

  /// No description provided for @statusVersion.
  ///
  /// In en, this message translates to:
  /// **'v{version}'**
  String statusVersion(Object version);

  /// No description provided for @backupManagement.
  ///
  /// In en, this message translates to:
  /// **'Backup Management'**
  String get backupManagement;

  /// No description provided for @backupList.
  ///
  /// In en, this message translates to:
  /// **'Backup List'**
  String get backupList;

  /// No description provided for @createBackup.
  ///
  /// In en, this message translates to:
  /// **'Create Backup'**
  String get createBackup;

  /// No description provided for @noBackupFiles.
  ///
  /// In en, this message translates to:
  /// **'No backup files'**
  String get noBackupFiles;

  /// No description provided for @clickCreateBackupTab.
  ///
  /// In en, this message translates to:
  /// **'Click the Create Backup tab to get started'**
  String get clickCreateBackupTab;

  /// No description provided for @importBackup.
  ///
  /// In en, this message translates to:
  /// **'Import Backup'**
  String get importBackup;

  /// No description provided for @previewContent.
  ///
  /// In en, this message translates to:
  /// **'Preview Content'**
  String get previewContent;

  /// No description provided for @exportFile.
  ///
  /// In en, this message translates to:
  /// **'Export File'**
  String get exportFile;

  /// No description provided for @restoreBackup.
  ///
  /// In en, this message translates to:
  /// **'Restore Backup'**
  String get restoreBackup;

  /// No description provided for @selectBackupToView.
  ///
  /// In en, this message translates to:
  /// **'Select a backup to view details'**
  String get selectBackupToView;

  /// No description provided for @database.
  ///
  /// In en, this message translates to:
  /// **'Database'**
  String get database;

  /// No description provided for @backupType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get backupType;

  /// No description provided for @backupSize.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get backupSize;

  /// No description provided for @createdAt.
  ///
  /// In en, this message translates to:
  /// **'Created At'**
  String get createdAt;

  /// No description provided for @tableCount.
  ///
  /// In en, this message translates to:
  /// **'Table Count'**
  String get tableCount;

  /// No description provided for @description.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get description;

  /// No description provided for @preview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get preview;

  /// No description provided for @export.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get export;

  /// No description provided for @restore.
  ///
  /// In en, this message translates to:
  /// **'Restore'**
  String get restore;

  /// No description provided for @confirmRestore.
  ///
  /// In en, this message translates to:
  /// **'Confirm Restore'**
  String get confirmRestore;

  /// No description provided for @confirmRestoreMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to restore backup \"{name}\"?\n\nThis will execute all SQL statements in the backup file and may overwrite existing data.'**
  String confirmRestoreMessage(Object name);

  /// No description provided for @confirmDelete.
  ///
  /// In en, this message translates to:
  /// **'Confirm Delete'**
  String get confirmDelete;

  /// No description provided for @confirmDeleteMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete backup \"{name}\"?\n\nThis action cannot be undone.'**
  String confirmDeleteMessage(Object name);

  /// No description provided for @backupFormat.
  ///
  /// In en, this message translates to:
  /// **'Backup Format'**
  String get backupFormat;

  /// No description provided for @backupContent.
  ///
  /// In en, this message translates to:
  /// **'Backup Content'**
  String get backupContent;

  /// No description provided for @selectTablesHint.
  ///
  /// In en, this message translates to:
  /// **'Select Tables (leave empty for all)'**
  String get selectTablesHint;

  /// No description provided for @advancedOptions.
  ///
  /// In en, this message translates to:
  /// **'Advanced Options'**
  String get advancedOptions;

  /// No description provided for @includeStructure.
  ///
  /// In en, this message translates to:
  /// **'Include Table Structure'**
  String get includeStructure;

  /// No description provided for @includeStructureDesc.
  ///
  /// In en, this message translates to:
  /// **'CREATE TABLE statements'**
  String get includeStructureDesc;

  /// No description provided for @includeData.
  ///
  /// In en, this message translates to:
  /// **'Include Data'**
  String get includeData;

  /// No description provided for @includeDataDesc.
  ///
  /// In en, this message translates to:
  /// **'INSERT statements or data rows'**
  String get includeDataDesc;

  /// No description provided for @noTablesAvailable.
  ///
  /// In en, this message translates to:
  /// **'No tables available'**
  String get noTablesAvailable;

  /// No description provided for @selectAll.
  ///
  /// In en, this message translates to:
  /// **'Select All'**
  String get selectAll;

  /// No description provided for @deselectAll.
  ///
  /// In en, this message translates to:
  /// **'Deselect All'**
  String get deselectAll;

  /// No description provided for @tablesSelected.
  ///
  /// In en, this message translates to:
  /// **'{count} tables selected'**
  String tablesSelected(Object count);

  /// No description provided for @addDropTable.
  ///
  /// In en, this message translates to:
  /// **'Add DROP TABLE'**
  String get addDropTable;

  /// No description provided for @useExtendedInsert.
  ///
  /// In en, this message translates to:
  /// **'Use Extended INSERT'**
  String get useExtendedInsert;

  /// No description provided for @useExtendedInsertDesc.
  ///
  /// In en, this message translates to:
  /// **'Combine multiple rows into one INSERT'**
  String get useExtendedInsertDesc;

  /// No description provided for @rowLimitPerTable.
  ///
  /// In en, this message translates to:
  /// **'Row Limit Per Table (optional)'**
  String get rowLimitPerTable;

  /// No description provided for @leaveEmptyForNoLimit.
  ///
  /// In en, this message translates to:
  /// **'Leave empty for no limit'**
  String get leaveEmptyForNoLimit;

  /// No description provided for @whereCondition.
  ///
  /// In en, this message translates to:
  /// **'WHERE Condition (optional)'**
  String get whereCondition;

  /// No description provided for @whereConditionExample.
  ///
  /// In en, this message translates to:
  /// **'e.g.: id > 100'**
  String get whereConditionExample;

  /// No description provided for @enterBackupDescription.
  ///
  /// In en, this message translates to:
  /// **'Enter backup description (optional)'**
  String get enterBackupDescription;

  /// No description provided for @startBackup.
  ///
  /// In en, this message translates to:
  /// **'Start Backup'**
  String get startBackup;

  /// No description provided for @backupProgress.
  ///
  /// In en, this message translates to:
  /// **'Backup Progress'**
  String get backupProgress;

  /// No description provided for @waitingToStartBackup.
  ///
  /// In en, this message translates to:
  /// **'Waiting to start backup...'**
  String get waitingToStartBackup;

  /// No description provided for @currentTable.
  ///
  /// In en, this message translates to:
  /// **'Current Table'**
  String get currentTable;

  /// No description provided for @progressPercent.
  ///
  /// In en, this message translates to:
  /// **'Progress'**
  String get progressPercent;

  /// No description provided for @backupComplete.
  ///
  /// In en, this message translates to:
  /// **'Backup Complete!'**
  String get backupComplete;

  /// No description provided for @backupFailed.
  ///
  /// In en, this message translates to:
  /// **'Backup Failed'**
  String get backupFailed;

  /// No description provided for @loadBackupListFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load backup list'**
  String get loadBackupListFailed;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get retry;

  /// No description provided for @previewFailed.
  ///
  /// In en, this message translates to:
  /// **'Preview failed'**
  String get previewFailed;

  /// No description provided for @exportedTo.
  ///
  /// In en, this message translates to:
  /// **'Exported to'**
  String get exportedTo;

  /// No description provided for @backupRestoreSuccess.
  ///
  /// In en, this message translates to:
  /// **'Backup restored successfully'**
  String get backupRestoreSuccess;

  /// No description provided for @restoreFailed.
  ///
  /// In en, this message translates to:
  /// **'Restore failed'**
  String get restoreFailed;

  /// No description provided for @backupDeleted.
  ///
  /// In en, this message translates to:
  /// **'Backup deleted'**
  String get backupDeleted;

  /// No description provided for @deleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Deletion failed: {error}'**
  String deleteFailed(Object error);

  /// No description provided for @selectBackupFile.
  ///
  /// In en, this message translates to:
  /// **'Select Backup File'**
  String get selectBackupFile;

  /// No description provided for @backupImportSuccess.
  ///
  /// In en, this message translates to:
  /// **'Backup file imported successfully'**
  String get backupImportSuccess;

  /// Generic import failure message
  ///
  /// In en, this message translates to:
  /// **'Import failed: {error}'**
  String importFailed(String error);

  /// No description provided for @selectAtLeastOneOption.
  ///
  /// In en, this message translates to:
  /// **'Please select at least one option (structure or data)'**
  String get selectAtLeastOneOption;

  /// No description provided for @backupFailedError.
  ///
  /// In en, this message translates to:
  /// **'Backup failed'**
  String get backupFailedError;

  /// No description provided for @aiAssistant.
  ///
  /// In en, this message translates to:
  /// **'AI Assistant'**
  String get aiAssistant;

  /// No description provided for @aiAnalyze.
  ///
  /// In en, this message translates to:
  /// **'AI Analyze'**
  String get aiAnalyze;

  /// No description provided for @aiAnalyzeTable.
  ///
  /// In en, this message translates to:
  /// **'AI Analyze Table'**
  String get aiAnalyzeTable;

  /// No description provided for @aiAnalyzeDatabase.
  ///
  /// In en, this message translates to:
  /// **'AI Analyze Database'**
  String get aiAnalyzeDatabase;

  /// No description provided for @aiAnalyzeServer.
  ///
  /// In en, this message translates to:
  /// **'AI Analyze Server'**
  String get aiAnalyzeServer;

  /// No description provided for @aiAnalyzeErrorResult.
  ///
  /// In en, this message translates to:
  /// **'AI Analyze Error'**
  String get aiAnalyzeErrorResult;

  /// No description provided for @aiAnalyzeNodeFailed.
  ///
  /// In en, this message translates to:
  /// **'AI analysis failed: {error}'**
  String aiAnalyzeNodeFailed(Object error);

  /// No description provided for @apiSettings.
  ///
  /// In en, this message translates to:
  /// **'API Settings'**
  String get apiSettings;

  /// No description provided for @clearChat.
  ///
  /// In en, this message translates to:
  /// **'Clear Chat'**
  String get clearChat;

  /// No description provided for @model.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get model;

  /// No description provided for @enterModelName.
  ///
  /// In en, this message translates to:
  /// **'Enter model name'**
  String get enterModelName;

  /// No description provided for @autoExecuteSql.
  ///
  /// In en, this message translates to:
  /// **'Auto Execute SQL'**
  String get autoExecuteSql;

  /// No description provided for @autoExecuteSqlDesc.
  ///
  /// In en, this message translates to:
  /// **'When enabled, AI-generated queries will be executed automatically'**
  String get autoExecuteSqlDesc;

  /// No description provided for @aiDatabaseAssistant.
  ///
  /// In en, this message translates to:
  /// **'AI Database Assistant'**
  String get aiDatabaseAssistant;

  /// No description provided for @aiAssistantDesc.
  ///
  /// In en, this message translates to:
  /// **'Supports multiple AI providers\nHelps you write SQL, optimize queries, explain database structure'**
  String get aiAssistantDesc;

  /// No description provided for @enterYourQuestion.
  ///
  /// In en, this message translates to:
  /// **'Enter your question...'**
  String get enterYourQuestion;

  /// No description provided for @configureApiKeyFirst.
  ///
  /// In en, this message translates to:
  /// **'Please configure the API key for {provider} in Settings first.\n\nClick the settings icon in the top right corner to get started.'**
  String configureApiKeyFirst(Object provider);

  /// No description provided for @generationFailed.
  ///
  /// In en, this message translates to:
  /// **'Generation failed'**
  String get generationFailed;

  /// No description provided for @stepAnalyzeNeeds.
  ///
  /// In en, this message translates to:
  /// **'Step 1: Analyzing user needs, determining tables to query...'**
  String get stepAnalyzeNeeds;

  /// No description provided for @stepGetTableSchema.
  ///
  /// In en, this message translates to:
  /// **'Step 2: Getting detailed table schemas...'**
  String get stepGetTableSchema;

  /// No description provided for @stepGenerateSql.
  ///
  /// In en, this message translates to:
  /// **'Step 3: Generating SQL statements...'**
  String get stepGenerateSql;

  /// No description provided for @analysisResultTables.
  ///
  /// In en, this message translates to:
  /// **'Analysis Result: Tables to query'**
  String get analysisResultTables;

  /// No description provided for @tableSchemaInfo.
  ///
  /// In en, this message translates to:
  /// **'Table Schema Information'**
  String get tableSchemaInfo;

  /// No description provided for @operationCancelled.
  ///
  /// In en, this message translates to:
  /// **'Operation cancelled'**
  String get operationCancelled;

  /// No description provided for @executingSql.
  ///
  /// In en, this message translates to:
  /// **'Executing SQL...'**
  String get executingSql;

  /// No description provided for @executeSuccessRows.
  ///
  /// In en, this message translates to:
  /// **'Execution successful. {count} rows returned.'**
  String executeSuccessRows(Object count);

  /// No description provided for @executeFailedError.
  ///
  /// In en, this message translates to:
  /// **'Execution failed'**
  String get executeFailedError;

  /// No description provided for @confirmDangerousOperation.
  ///
  /// In en, this message translates to:
  /// **'Confirm Dangerous Operation?'**
  String get confirmDangerousOperation;

  /// No description provided for @confirmExecuteSql.
  ///
  /// In en, this message translates to:
  /// **'Confirm Execute SQL'**
  String get confirmExecuteSql;

  /// No description provided for @dangerousOperationWarning.
  ///
  /// In en, this message translates to:
  /// **'This operation may modify or delete data. Please proceed with caution!'**
  String get dangerousOperationWarning;

  /// No description provided for @sqlCopied.
  ///
  /// In en, this message translates to:
  /// **'SQL copied'**
  String get sqlCopied;

  /// No description provided for @sqlGenerationComplete.
  ///
  /// In en, this message translates to:
  /// **'SQL Generation Complete'**
  String get sqlGenerationComplete;

  /// No description provided for @dangerousOperation.
  ///
  /// In en, this message translates to:
  /// **'Dangerous Operation'**
  String get dangerousOperation;

  /// No description provided for @dangerousOperationDesc.
  ///
  /// In en, this message translates to:
  /// **'This is a dangerous operation. Please handle with care.'**
  String get dangerousOperationDesc;

  /// No description provided for @taskCompleteDesc.
  ///
  /// In en, this message translates to:
  /// **'Task completed. You can choose to execute or copy the SQL.'**
  String get taskCompleteDesc;

  /// No description provided for @generatedSql.
  ///
  /// In en, this message translates to:
  /// **'Generated SQL'**
  String get generatedSql;

  /// No description provided for @dangerous.
  ///
  /// In en, this message translates to:
  /// **'Dangerous'**
  String get dangerous;

  /// No description provided for @confirmExecute.
  ///
  /// In en, this message translates to:
  /// **'Confirm Execute'**
  String get confirmExecute;

  /// No description provided for @requestTimeout.
  ///
  /// In en, this message translates to:
  /// **'Request Timeout'**
  String get requestTimeout;

  /// No description provided for @seconds.
  ///
  /// In en, this message translates to:
  /// **'seconds'**
  String get seconds;

  /// No description provided for @apiSettingsSaved.
  ///
  /// In en, this message translates to:
  /// **'API settings saved'**
  String get apiSettingsSaved;

  /// No description provided for @dataImport.
  ///
  /// In en, this message translates to:
  /// **'Data Import'**
  String get dataImport;

  /// No description provided for @selectFile.
  ///
  /// In en, this message translates to:
  /// **'Select File'**
  String get selectFile;

  /// No description provided for @noFileSelected.
  ///
  /// In en, this message translates to:
  /// **'No file selected'**
  String get noFileSelected;

  /// No description provided for @importConfig.
  ///
  /// In en, this message translates to:
  /// **'Import Configuration'**
  String get importConfig;

  /// No description provided for @targetTableName.
  ///
  /// In en, this message translates to:
  /// **'Target Table Name'**
  String get targetTableName;

  /// No description provided for @enterTableName.
  ///
  /// In en, this message translates to:
  /// **'Enter table name'**
  String get enterTableName;

  /// No description provided for @includeHeader.
  ///
  /// In en, this message translates to:
  /// **'Include Header'**
  String get includeHeader;

  /// No description provided for @delimiter.
  ///
  /// In en, this message translates to:
  /// **'Delimiter'**
  String get delimiter;

  /// No description provided for @overwriteTable.
  ///
  /// In en, this message translates to:
  /// **'Overwrite Table'**
  String get overwriteTable;

  /// No description provided for @deleteExistingTable.
  ///
  /// In en, this message translates to:
  /// **'(Delete existing table)'**
  String get deleteExistingTable;

  /// No description provided for @batchSize.
  ///
  /// In en, this message translates to:
  /// **'Batch Size'**
  String get batchSize;

  /// No description provided for @dataPreviewRows.
  ///
  /// In en, this message translates to:
  /// **'Data Preview ({count} rows)'**
  String dataPreviewRows(Object count);

  /// No description provided for @pleaseSelectFile.
  ///
  /// In en, this message translates to:
  /// **'Please select a file to preview the data'**
  String get pleaseSelectFile;

  /// No description provided for @importProgress.
  ///
  /// In en, this message translates to:
  /// **'Import Progress'**
  String get importProgress;

  /// No description provided for @importPreparing.
  ///
  /// In en, this message translates to:
  /// **'Preparing import...'**
  String get importPreparing;

  /// No description provided for @totalRecords.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get totalRecords;

  /// No description provided for @importedRecords.
  ///
  /// In en, this message translates to:
  /// **'Imported'**
  String get importedRecords;

  /// No description provided for @failedRecords.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get failedRecords;

  /// No description provided for @readyToImport.
  ///
  /// In en, this message translates to:
  /// **'Ready to import'**
  String get readyToImport;

  /// No description provided for @importingData.
  ///
  /// In en, this message translates to:
  /// **'Importing data...'**
  String get importingData;

  /// No description provided for @importComplete.
  ///
  /// In en, this message translates to:
  /// **'Import complete!'**
  String get importComplete;

  /// No description provided for @parseFileFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to parse file'**
  String get parseFileFailed;

  /// No description provided for @noDataToImport.
  ///
  /// In en, this message translates to:
  /// **'No data to import'**
  String get noDataToImport;

  /// No description provided for @selectDatabaseFirst.
  ///
  /// In en, this message translates to:
  /// **'Please select a database first'**
  String get selectDatabaseFirst;

  /// No description provided for @importFailedError.
  ///
  /// In en, this message translates to:
  /// **'Import failed'**
  String get importFailedError;

  /// No description provided for @startImport.
  ///
  /// In en, this message translates to:
  /// **'Start Import'**
  String get startImport;

  /// No description provided for @importing.
  ///
  /// In en, this message translates to:
  /// **'Importing...'**
  String get importing;

  /// No description provided for @optimizeSql.
  ///
  /// In en, this message translates to:
  /// **'Optimize SQL'**
  String get optimizeSql;

  /// No description provided for @explainQuery.
  ///
  /// In en, this message translates to:
  /// **'Explain Query'**
  String get explainQuery;

  /// No description provided for @generateInsert.
  ///
  /// In en, this message translates to:
  /// **'Generate INSERT'**
  String get generateInsert;

  /// No description provided for @generateUpdate.
  ///
  /// In en, this message translates to:
  /// **'Generate UPDATE'**
  String get generateUpdate;

  /// No description provided for @generateDelete.
  ///
  /// In en, this message translates to:
  /// **'Generate DELETE'**
  String get generateDelete;

  /// No description provided for @createTableStatement.
  ///
  /// In en, this message translates to:
  /// **'Create Table Statement'**
  String get createTableStatement;

  /// No description provided for @securityCheck.
  ///
  /// In en, this message translates to:
  /// **'Security Check'**
  String get securityCheck;

  /// No description provided for @indexSuggestion.
  ///
  /// In en, this message translates to:
  /// **'Index Suggestion'**
  String get indexSuggestion;

  /// No description provided for @executionPlan.
  ///
  /// In en, this message translates to:
  /// **'Execution Plan'**
  String get executionPlan;

  /// No description provided for @pleaseEnterSql.
  ///
  /// In en, this message translates to:
  /// **'Please enter an SQL statement first'**
  String get pleaseEnterSql;

  /// No description provided for @pleaseConnectDatabase.
  ///
  /// In en, this message translates to:
  /// **'Please connect to a database first'**
  String get pleaseConnectDatabase;

  /// No description provided for @analysisFailed.
  ///
  /// In en, this message translates to:
  /// **'Analysis failed'**
  String get analysisFailed;

  /// No description provided for @loadHistoryFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load query history'**
  String get loadHistoryFailed;

  /// No description provided for @noQueryHistory.
  ///
  /// In en, this message translates to:
  /// **'No query history yet\n\nAfter executing SQL queries, history will be saved here.'**
  String get noQueryHistory;

  /// No description provided for @queryHistoryRecords.
  ///
  /// In en, this message translates to:
  /// **'Query History (Recent {count} records)'**
  String queryHistoryRecords(Object count);

  /// No description provided for @databaseType.
  ///
  /// In en, this message translates to:
  /// **'Database Type'**
  String get databaseType;

  /// No description provided for @server.
  ///
  /// In en, this message translates to:
  /// **'Server'**
  String get server;

  /// No description provided for @currentDatabase.
  ///
  /// In en, this message translates to:
  /// **'Current Database'**
  String get currentDatabase;

  /// No description provided for @notConnected.
  ///
  /// In en, this message translates to:
  /// **'Not Connected'**
  String get notConnected;

  /// No description provided for @notSelected.
  ///
  /// In en, this message translates to:
  /// **'Not Selected'**
  String get notSelected;

  /// No description provided for @tableName.
  ///
  /// In en, this message translates to:
  /// **'Table Name'**
  String get tableName;

  /// No description provided for @tableStructureInfo.
  ///
  /// In en, this message translates to:
  /// **'Table Structure Information'**
  String get tableStructureInfo;

  /// No description provided for @createStatement.
  ///
  /// In en, this message translates to:
  /// **'Create Statement'**
  String get createStatement;

  /// No description provided for @andMoreTables.
  ///
  /// In en, this message translates to:
  /// **'... and {count} more tables'**
  String andMoreTables(Object count);

  /// No description provided for @primaryKey.
  ///
  /// In en, this message translates to:
  /// **'Primary Key'**
  String get primaryKey;

  /// No description provided for @executionTime.
  ///
  /// In en, this message translates to:
  /// **'Execution Time'**
  String get executionTime;

  /// No description provided for @status.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get status;

  /// No description provided for @commonFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get commonFailed;

  /// No description provided for @format.
  ///
  /// In en, this message translates to:
  /// **'Format'**
  String get format;

  /// No description provided for @connectionDefaultDatabase.
  ///
  /// In en, this message translates to:
  /// **'Default Database'**
  String get connectionDefaultDatabase;

  /// No description provided for @connectionSavePassword.
  ///
  /// In en, this message translates to:
  /// **'Save Password'**
  String get connectionSavePassword;

  /// No description provided for @connectionAdvancedOptions.
  ///
  /// In en, this message translates to:
  /// **'Advanced Options'**
  String get connectionAdvancedOptions;

  /// No description provided for @connectionTimeout.
  ///
  /// In en, this message translates to:
  /// **'Timeout (seconds)'**
  String get connectionTimeout;

  /// No description provided for @connectionUseSSL.
  ///
  /// In en, this message translates to:
  /// **'Use SSL/TLS'**
  String get connectionUseSSL;

  /// No description provided for @connectionEnableSecureConnection.
  ///
  /// In en, this message translates to:
  /// **'Enable secure connection'**
  String get connectionEnableSecureConnection;

  /// No description provided for @connectionUseTls.
  ///
  /// In en, this message translates to:
  /// **'Use TLS/SSL'**
  String get connectionUseTls;

  /// No description provided for @connectionUseTlsDesc.
  ///
  /// In en, this message translates to:
  /// **'Encrypt the connection via TLS (established on the server side)'**
  String get connectionUseTlsDesc;

  /// No description provided for @connectionTlsInsecure.
  ///
  /// In en, this message translates to:
  /// **'Skip certificate verification (unsafe)'**
  String get connectionTlsInsecure;

  /// No description provided for @connectionTlsInsecureDesc.
  ///
  /// In en, this message translates to:
  /// **'Do not verify the server certificate — trusted/test environments only'**
  String get connectionTlsInsecureDesc;

  /// No description provided for @connectionSshSubtitleGateway.
  ///
  /// In en, this message translates to:
  /// **'SSH tunnel established by the dbmaster server (config travels with the connection)'**
  String get connectionSshSubtitleGateway;

  /// No description provided for @connectionAutoReconnect.
  ///
  /// In en, this message translates to:
  /// **'Auto Reconnect'**
  String get connectionAutoReconnect;

  /// No description provided for @connectionAutoReconnectDesc.
  ///
  /// In en, this message translates to:
  /// **'Automatically try to reconnect when connection is lost'**
  String get connectionAutoReconnectDesc;

  /// No description provided for @connectionCharset.
  ///
  /// In en, this message translates to:
  /// **'Character Set'**
  String get connectionCharset;

  /// No description provided for @connectionTimezone.
  ///
  /// In en, this message translates to:
  /// **'Time Zone'**
  String get connectionTimezone;

  /// No description provided for @connectionTestSuccess.
  ///
  /// In en, this message translates to:
  /// **'Connection successful!'**
  String get connectionTestSuccess;

  /// Error dialog content when connection test fails
  ///
  /// In en, this message translates to:
  /// **'Test failed: {error}'**
  String connectionTestFailed(String error);

  /// No description provided for @connectionDatabaseType.
  ///
  /// In en, this message translates to:
  /// **'Database Type'**
  String get connectionDatabaseType;

  /// No description provided for @connectionManager.
  ///
  /// In en, this message translates to:
  /// **'Connection Manager'**
  String get connectionManager;

  /// No description provided for @connectionSavedConnections.
  ///
  /// In en, this message translates to:
  /// **'Saved Connections'**
  String get connectionSavedConnections;

  /// No description provided for @connectionNoSavedConnections.
  ///
  /// In en, this message translates to:
  /// **'No saved connections'**
  String get connectionNoSavedConnections;

  /// No description provided for @connectionCurrent.
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get connectionCurrent;

  /// No description provided for @connectionConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get connectionConnected;

  /// No description provided for @connectionSwitchToConnection.
  ///
  /// In en, this message translates to:
  /// **'Switch to this connection'**
  String get connectionSwitchToConnection;

  /// No description provided for @connectionCloneConnection.
  ///
  /// In en, this message translates to:
  /// **'Clone Connection'**
  String get connectionCloneConnection;

  /// No description provided for @connectionCloned.
  ///
  /// In en, this message translates to:
  /// **'Connection cloned'**
  String get connectionCloned;

  /// No description provided for @connectionDeleteConnectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete Connection'**
  String get connectionDeleteConnectionTitle;

  /// No description provided for @connectionDeleteConnectionConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete connection'**
  String get connectionDeleteConnectionConfirm;

  /// No description provided for @connectionDisconnectAll.
  ///
  /// In en, this message translates to:
  /// **'Disconnect All'**
  String get connectionDisconnectAll;

  /// No description provided for @searchDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get searchDialogTitle;

  /// No description provided for @searchHint.
  ///
  /// In en, this message translates to:
  /// **'Search tables, views, stored procedures, columns...'**
  String get searchHint;

  /// No description provided for @searchNoResults.
  ///
  /// In en, this message translates to:
  /// **'No objects found'**
  String get searchNoResults;

  /// No description provided for @searchTryDifferentKeywords.
  ///
  /// In en, this message translates to:
  /// **'Try different keywords'**
  String get searchTryDifferentKeywords;

  /// No description provided for @searchNavigate.
  ///
  /// In en, this message translates to:
  /// **'Navigate'**
  String get searchNavigate;

  /// No description provided for @searchSelect.
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get searchSelect;

  /// No description provided for @searchClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get searchClose;

  /// No description provided for @searchResultsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} results'**
  String searchResultsCount(Object count);

  /// No description provided for @searchTypeConnection.
  ///
  /// In en, this message translates to:
  /// **'Connection'**
  String get searchTypeConnection;

  /// No description provided for @searchTypeDatabase.
  ///
  /// In en, this message translates to:
  /// **'Database'**
  String get searchTypeDatabase;

  /// No description provided for @searchTypeTable.
  ///
  /// In en, this message translates to:
  /// **'Table'**
  String get searchTypeTable;

  /// No description provided for @searchTypeView.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get searchTypeView;

  /// No description provided for @searchTypeProcedure.
  ///
  /// In en, this message translates to:
  /// **'Procedure'**
  String get searchTypeProcedure;

  /// No description provided for @searchTypeColumn.
  ///
  /// In en, this message translates to:
  /// **'Column'**
  String get searchTypeColumn;

  /// No description provided for @savedQueriesTitle.
  ///
  /// In en, this message translates to:
  /// **'Saved Queries'**
  String get savedQueriesTitle;

  /// No description provided for @savedQueriesNoQueries.
  ///
  /// In en, this message translates to:
  /// **'No saved queries'**
  String get savedQueriesNoQueries;

  /// No description provided for @savedQueriesDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete Query'**
  String get savedQueriesDeleteTitle;

  /// No description provided for @savedQueriesDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this query?'**
  String get savedQueriesDeleteConfirm;

  /// No description provided for @savedQueriesOpen.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get savedQueriesOpen;

  /// Context menu item to open JSON cell viewer
  ///
  /// In en, this message translates to:
  /// **'View JSON'**
  String get viewJson;

  /// Context menu item to extract a JSON field as a new column
  ///
  /// In en, this message translates to:
  /// **'Extract field as column'**
  String get extractFieldAsColumn;

  /// No description provided for @erDiagramTitle.
  ///
  /// In en, this message translates to:
  /// **'ER Diagram'**
  String get erDiagramTitle;

  /// No description provided for @erDiagramSearchTables.
  ///
  /// In en, this message translates to:
  /// **'Search tables...'**
  String get erDiagramSearchTables;

  /// No description provided for @erDiagramHierarchicalLayout.
  ///
  /// In en, this message translates to:
  /// **'Hierarchical Layout'**
  String get erDiagramHierarchicalLayout;

  /// No description provided for @erDiagramForceDirectedLayout.
  ///
  /// In en, this message translates to:
  /// **'Force Directed Layout'**
  String get erDiagramForceDirectedLayout;

  /// No description provided for @erDiagramCircleLayout.
  ///
  /// In en, this message translates to:
  /// **'Circle Layout'**
  String get erDiagramCircleLayout;

  /// No description provided for @erDiagramResetLayout.
  ///
  /// In en, this message translates to:
  /// **'Reset Layout'**
  String get erDiagramResetLayout;

  /// No description provided for @erDiagramZoomIn.
  ///
  /// In en, this message translates to:
  /// **'Zoom In'**
  String get erDiagramZoomIn;

  /// No description provided for @erDiagramZoomOut.
  ///
  /// In en, this message translates to:
  /// **'Zoom Out'**
  String get erDiagramZoomOut;

  /// No description provided for @erDiagramFitToScreen.
  ///
  /// In en, this message translates to:
  /// **'Fit to Screen'**
  String get erDiagramFitToScreen;

  /// No description provided for @erDiagramRelations.
  ///
  /// In en, this message translates to:
  /// **'Relations'**
  String get erDiagramRelations;

  /// No description provided for @erDiagramZoom.
  ///
  /// In en, this message translates to:
  /// **'Zoom'**
  String get erDiagramZoom;

  /// No description provided for @erDiagramShowIsolated.
  ///
  /// In en, this message translates to:
  /// **'Show Isolated'**
  String get erDiagramShowIsolated;

  /// No description provided for @erDiagramExportAsPNG.
  ///
  /// In en, this message translates to:
  /// **'Export as PNG'**
  String get erDiagramExportAsPNG;

  /// No description provided for @erDiagramExportAsJPG.
  ///
  /// In en, this message translates to:
  /// **'Export as JPG'**
  String get erDiagramExportAsJPG;

  /// No description provided for @erDiagramLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading ER Diagram...'**
  String get erDiagramLoading;

  /// No description provided for @erDiagramErrorLoading.
  ///
  /// In en, this message translates to:
  /// **'Error loading ER Diagram'**
  String get erDiagramErrorLoading;

  /// No description provided for @erDiagramNoData.
  ///
  /// In en, this message translates to:
  /// **'No diagram data available'**
  String get erDiagramNoData;

  /// No description provided for @erDiagramRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get erDiagramRetry;

  /// No description provided for @erDiagramSelectConnection.
  ///
  /// In en, this message translates to:
  /// **'Select Connection'**
  String get erDiagramSelectConnection;

  /// No description provided for @erDiagramSelectDatabase.
  ///
  /// In en, this message translates to:
  /// **'Select Database'**
  String get erDiagramSelectDatabase;

  /// No description provided for @performanceAnalyzerTitle.
  ///
  /// In en, this message translates to:
  /// **'Performance Analyzer'**
  String get performanceAnalyzerTitle;

  /// No description provided for @performanceAnalyzerSearch.
  ///
  /// In en, this message translates to:
  /// **'Search...'**
  String get performanceAnalyzerSearch;

  /// No description provided for @performanceAnalyzerRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh Data'**
  String get performanceAnalyzerRefresh;

  /// No description provided for @performanceAnalyzerGenerateReport.
  ///
  /// In en, this message translates to:
  /// **'Generate Report'**
  String get performanceAnalyzerGenerateReport;

  /// No description provided for @performanceAnalyzerExport.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get performanceAnalyzerExport;

  /// No description provided for @performanceAnalyzerClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get performanceAnalyzerClose;

  /// No description provided for @performanceAnalyzerNotConnected.
  ///
  /// In en, this message translates to:
  /// **'Not Connected to Database'**
  String get performanceAnalyzerNotConnected;

  /// No description provided for @performanceAnalyzerNotConnectedDesc.
  ///
  /// In en, this message translates to:
  /// **'Please connect to a database first to use performance analysis'**
  String get performanceAnalyzerNotConnectedDesc;

  /// No description provided for @performanceAnalyzerConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get performanceAnalyzerConfirm;

  /// No description provided for @performanceAnalyzerSlowQueryAnalysis.
  ///
  /// In en, this message translates to:
  /// **'Slow Query Analysis'**
  String get performanceAnalyzerSlowQueryAnalysis;

  /// No description provided for @performanceAnalyzerIndexAnalysis.
  ///
  /// In en, this message translates to:
  /// **'Index Analysis'**
  String get performanceAnalyzerIndexAnalysis;

  /// No description provided for @performanceAnalyzerTableStatistics.
  ///
  /// In en, this message translates to:
  /// **'Table Statistics'**
  String get performanceAnalyzerTableStatistics;

  /// No description provided for @performanceAnalyzerPerformanceReport.
  ///
  /// In en, this message translates to:
  /// **'Performance Report'**
  String get performanceAnalyzerPerformanceReport;

  /// No description provided for @performanceAnalyzerLoading.
  ///
  /// In en, this message translates to:
  /// **'Analyzing database performance...'**
  String get performanceAnalyzerLoading;

  /// No description provided for @performanceAnalyzerLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Load Failed'**
  String get performanceAnalyzerLoadFailed;

  /// No description provided for @performanceAnalyzerRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get performanceAnalyzerRetry;

  /// No description provided for @performanceAnalyzerTimeThreshold.
  ///
  /// In en, this message translates to:
  /// **'Time Threshold:'**
  String get performanceAnalyzerTimeThreshold;

  /// No description provided for @performanceAnalyzerNoSlowQueries.
  ///
  /// In en, this message translates to:
  /// **'No slow queries found'**
  String get performanceAnalyzerNoSlowQueries;

  /// No description provided for @performanceAnalyzerSelectQuery.
  ///
  /// In en, this message translates to:
  /// **'Select a query to view details'**
  String get performanceAnalyzerSelectQuery;

  /// No description provided for @performanceAnalyzerQueryInfo.
  ///
  /// In en, this message translates to:
  /// **'Query Information'**
  String get performanceAnalyzerQueryInfo;

  /// No description provided for @performanceAnalyzerExecutionTime.
  ///
  /// In en, this message translates to:
  /// **'Execution Time'**
  String get performanceAnalyzerExecutionTime;

  /// No description provided for @performanceAnalyzerDatabase.
  ///
  /// In en, this message translates to:
  /// **'Database'**
  String get performanceAnalyzerDatabase;

  /// No description provided for @performanceAnalyzerRowsScaned.
  ///
  /// In en, this message translates to:
  /// **'Rows Scanned'**
  String get performanceAnalyzerRowsScaned;

  /// No description provided for @performanceAnalyzerRowsReturned.
  ///
  /// In en, this message translates to:
  /// **'Rows Returned'**
  String get performanceAnalyzerRowsReturned;

  /// No description provided for @performanceAnalyzerTimestamp.
  ///
  /// In en, this message translates to:
  /// **'Execution Time'**
  String get performanceAnalyzerTimestamp;

  /// No description provided for @performanceAnalyzerSqlStatement.
  ///
  /// In en, this message translates to:
  /// **'SQL Statement'**
  String get performanceAnalyzerSqlStatement;

  /// No description provided for @performanceAnalyzerExecutionPlan.
  ///
  /// In en, this message translates to:
  /// **'Execution Plan'**
  String get performanceAnalyzerExecutionPlan;

  /// No description provided for @performanceAnalyzerOptimizationSuggestions.
  ///
  /// In en, this message translates to:
  /// **'Optimization Suggestions'**
  String get performanceAnalyzerOptimizationSuggestions;

  /// No description provided for @performanceAnalyzerFullTableScan.
  ///
  /// In en, this message translates to:
  /// **'Full Table Scan Detected'**
  String get performanceAnalyzerFullTableScan;

  /// No description provided for @performanceAnalyzerFullTableScanDesc.
  ///
  /// In en, this message translates to:
  /// **'Query uses full table scan (type=ALL), consider adding index on WHERE clause columns'**
  String get performanceAnalyzerFullTableScanDesc;

  /// No description provided for @performanceAnalyzerFileSort.
  ///
  /// In en, this message translates to:
  /// **'File Sort'**
  String get performanceAnalyzerFileSort;

  /// No description provided for @performanceAnalyzerFileSortDesc.
  ///
  /// In en, this message translates to:
  /// **'Query uses file sort (Using filesort), consider adding index on ORDER BY columns'**
  String get performanceAnalyzerFileSortDesc;

  /// No description provided for @performanceAnalyzerTempTable.
  ///
  /// In en, this message translates to:
  /// **'Temporary Table Usage'**
  String get performanceAnalyzerTempTable;

  /// No description provided for @performanceAnalyzerTempTableDesc.
  ///
  /// In en, this message translates to:
  /// **'Query uses temporary table (Using temporary), consider optimizing GROUP BY or DISTINCT queries'**
  String get performanceAnalyzerTempTableDesc;

  /// No description provided for @performanceAnalyzerLowScanEfficiency.
  ///
  /// In en, this message translates to:
  /// **'Low Scan Efficiency'**
  String get performanceAnalyzerLowScanEfficiency;

  /// No description provided for @performanceAnalyzerNoIssues.
  ///
  /// In en, this message translates to:
  /// **'No Obvious Issues'**
  String get performanceAnalyzerNoIssues;

  /// No description provided for @performanceAnalyzerNoIssuesDesc.
  ///
  /// In en, this message translates to:
  /// **'Query execution plan looks normal'**
  String get performanceAnalyzerNoIssuesDesc;

  /// No description provided for @performanceAnalyzerIndexTypeDistribution.
  ///
  /// In en, this message translates to:
  /// **'Index Type Distribution'**
  String get performanceAnalyzerIndexTypeDistribution;

  /// No description provided for @performanceAnalyzerNoData.
  ///
  /// In en, this message translates to:
  /// **'No Data'**
  String get performanceAnalyzerNoData;

  /// No description provided for @performanceAnalyzerTotalIndexes.
  ///
  /// In en, this message translates to:
  /// **'Total Indexes'**
  String get performanceAnalyzerTotalIndexes;

  /// No description provided for @performanceAnalyzerUsedIndexes.
  ///
  /// In en, this message translates to:
  /// **'Used'**
  String get performanceAnalyzerUsedIndexes;

  /// No description provided for @performanceAnalyzerUnusedIndexes.
  ///
  /// In en, this message translates to:
  /// **'Unused'**
  String get performanceAnalyzerUnusedIndexes;

  /// No description provided for @performanceAnalyzerIndexes.
  ///
  /// In en, this message translates to:
  /// **'indexes'**
  String get performanceAnalyzerIndexes;

  /// No description provided for @performanceAnalyzerColumns.
  ///
  /// In en, this message translates to:
  /// **'Columns:'**
  String get performanceAnalyzerColumns;

  /// No description provided for @performanceAnalyzerCardinality.
  ///
  /// In en, this message translates to:
  /// **'Cardinality:'**
  String get performanceAnalyzerCardinality;

  /// No description provided for @performanceAnalyzerTotalTables.
  ///
  /// In en, this message translates to:
  /// **'Total Tables'**
  String get performanceAnalyzerTotalTables;

  /// No description provided for @performanceAnalyzerTotalRows.
  ///
  /// In en, this message translates to:
  /// **'Total Rows'**
  String get performanceAnalyzerTotalRows;

  /// No description provided for @performanceAnalyzerDataSize.
  ///
  /// In en, this message translates to:
  /// **'Data Size'**
  String get performanceAnalyzerDataSize;

  /// No description provided for @performanceAnalyzerIndexSize.
  ///
  /// In en, this message translates to:
  /// **'Index Size'**
  String get performanceAnalyzerIndexSize;

  /// No description provided for @performanceAnalyzerTotalSize.
  ///
  /// In en, this message translates to:
  /// **'Total Size'**
  String get performanceAnalyzerTotalSize;

  /// No description provided for @performanceAnalyzerTableName.
  ///
  /// In en, this message translates to:
  /// **'Table Name'**
  String get performanceAnalyzerTableName;

  /// No description provided for @performanceAnalyzerEngine.
  ///
  /// In en, this message translates to:
  /// **'Engine'**
  String get performanceAnalyzerEngine;

  /// No description provided for @performanceAnalyzerRowCount.
  ///
  /// In en, this message translates to:
  /// **'Row Count'**
  String get performanceAnalyzerRowCount;

  /// No description provided for @performanceAnalyzerPercentage.
  ///
  /// In en, this message translates to:
  /// **'Percentage'**
  String get performanceAnalyzerPercentage;

  /// No description provided for @performanceAnalyzerTableSizeDistribution.
  ///
  /// In en, this message translates to:
  /// **'Table Size Distribution (Top 10)'**
  String get performanceAnalyzerTableSizeDistribution;

  /// No description provided for @performanceAnalyzerDatabasePerformanceReport.
  ///
  /// In en, this message translates to:
  /// **'Database Performance Report'**
  String get performanceAnalyzerDatabasePerformanceReport;

  /// No description provided for @performanceAnalyzerGeneratedAt.
  ///
  /// In en, this message translates to:
  /// **'Generated At:'**
  String get performanceAnalyzerGeneratedAt;

  /// No description provided for @performanceAnalyzerTableCount.
  ///
  /// In en, this message translates to:
  /// **'Table Count'**
  String get performanceAnalyzerTableCount;

  /// No description provided for @performanceAnalyzerSlowQueries.
  ///
  /// In en, this message translates to:
  /// **'Slow Queries'**
  String get performanceAnalyzerSlowQueries;

  /// No description provided for @performanceAnalyzerSuggestions.
  ///
  /// In en, this message translates to:
  /// **'Suggestions'**
  String get performanceAnalyzerSuggestions;

  /// No description provided for @performanceAnalyzerImpact.
  ///
  /// In en, this message translates to:
  /// **'Impact:'**
  String get performanceAnalyzerImpact;

  /// No description provided for @performanceAnalyzerImpactHigh.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get performanceAnalyzerImpactHigh;

  /// No description provided for @performanceAnalyzerImpactMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get performanceAnalyzerImpactMedium;

  /// No description provided for @performanceAnalyzerImpactLow.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get performanceAnalyzerImpactLow;

  /// No description provided for @performanceAnalyzerRecommendation.
  ///
  /// In en, this message translates to:
  /// **'Recommendation:'**
  String get performanceAnalyzerRecommendation;

  /// No description provided for @performanceAnalyzerSlowQueriesTop.
  ///
  /// In en, this message translates to:
  /// **'Slow Queries Top'**
  String get performanceAnalyzerSlowQueriesTop;

  /// No description provided for @performanceAnalyzerLargeTableStatistics.
  ///
  /// In en, this message translates to:
  /// **'Large Table Statistics'**
  String get performanceAnalyzerLargeTableStatistics;

  /// No description provided for @performanceAnalyzerClickGenerateReport.
  ///
  /// In en, this message translates to:
  /// **'Click \"Generate Report\" button to start analysis'**
  String get performanceAnalyzerClickGenerateReport;

  /// No description provided for @sqlHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'SQL History'**
  String get sqlHistoryTitle;

  /// No description provided for @sqlHistoryNoHistory.
  ///
  /// In en, this message translates to:
  /// **'No history yet'**
  String get sqlHistoryNoHistory;

  /// No description provided for @sqlHistoryClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get sqlHistoryClose;

  /// No description provided for @sqlHistoryDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get sqlHistoryDelete;

  /// No description provided for @sqlHistoryConfirmDelete.
  ///
  /// In en, this message translates to:
  /// **'Confirm Delete'**
  String get sqlHistoryConfirmDelete;

  /// No description provided for @sqlHistoryDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this history record?'**
  String get sqlHistoryDeleteConfirm;

  /// No description provided for @sqlHistoryJustNow.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get sqlHistoryJustNow;

  /// No description provided for @sqlHistoryMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} minutes ago'**
  String sqlHistoryMinutesAgo(Object count);

  /// No description provided for @sqlHistoryHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} hours ago'**
  String sqlHistoryHoursAgo(Object count);

  /// No description provided for @sqlHistoryDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} days ago'**
  String sqlHistoryDaysAgo(Object count);

  /// No description provided for @aiPanelApiSettings.
  ///
  /// In en, this message translates to:
  /// **'API Settings'**
  String get aiPanelApiSettings;

  /// No description provided for @aiPanelApiKey.
  ///
  /// In en, this message translates to:
  /// **'API Key'**
  String get aiPanelApiKey;

  /// No description provided for @aiPanelEnterApiKey.
  ///
  /// In en, this message translates to:
  /// **'Enter API key'**
  String get aiPanelEnterApiKey;

  /// No description provided for @aiPanelApiBaseUrl.
  ///
  /// In en, this message translates to:
  /// **'API Base URL (optional)'**
  String get aiPanelApiBaseUrl;

  /// No description provided for @aiPanelCustomApiUrl.
  ///
  /// In en, this message translates to:
  /// **'Custom API URL'**
  String get aiPanelCustomApiUrl;

  /// No description provided for @aiPanelRequestTimeout.
  ///
  /// In en, this message translates to:
  /// **'Request Timeout:'**
  String get aiPanelRequestTimeout;

  /// No description provided for @aiPanelSeconds.
  ///
  /// In en, this message translates to:
  /// **'seconds'**
  String get aiPanelSeconds;

  /// No description provided for @aiPanelSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get aiPanelSave;

  /// No description provided for @aiPanelApiSettingsSaved.
  ///
  /// In en, this message translates to:
  /// **'API settings saved'**
  String get aiPanelApiSettingsSaved;

  /// No description provided for @aiPanelConfirmDangerousOperation.
  ///
  /// In en, this message translates to:
  /// **'Confirm Dangerous Operation?'**
  String get aiPanelConfirmDangerousOperation;

  /// No description provided for @aiPanelConfirmExecuteSql.
  ///
  /// In en, this message translates to:
  /// **'Confirm Execute SQL'**
  String get aiPanelConfirmExecuteSql;

  /// No description provided for @aiPanelDangerousOperationWarning.
  ///
  /// In en, this message translates to:
  /// **'This operation may modify or delete data. Please proceed with caution!'**
  String get aiPanelDangerousOperationWarning;

  /// No description provided for @aiPanelCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get aiPanelCancel;

  /// No description provided for @aiPanelConfirmExecute.
  ///
  /// In en, this message translates to:
  /// **'Confirm Execute'**
  String get aiPanelConfirmExecute;

  /// No description provided for @aiPanelOperationCancelled.
  ///
  /// In en, this message translates to:
  /// **'Operation cancelled'**
  String get aiPanelOperationCancelled;

  /// No description provided for @aiPanelExecutingSql.
  ///
  /// In en, this message translates to:
  /// **'Executing SQL...'**
  String get aiPanelExecutingSql;

  /// No description provided for @aiPanelExecuteSuccess.
  ///
  /// In en, this message translates to:
  /// **'Execution successful. {count} rows returned.'**
  String aiPanelExecuteSuccess(Object count);

  /// No description provided for @aiPanelExecuteFailed.
  ///
  /// In en, this message translates to:
  /// **'Execution failed'**
  String get aiPanelExecuteFailed;

  /// No description provided for @aiPanelDataPreview.
  ///
  /// In en, this message translates to:
  /// **'Data Preview'**
  String get aiPanelDataPreview;

  /// No description provided for @aiPanelAndMoreRows.
  ///
  /// In en, this message translates to:
  /// **'and {count} more rows'**
  String aiPanelAndMoreRows(Object count);

  /// No description provided for @aiPanelSqlExecutionSuccess.
  ///
  /// In en, this message translates to:
  /// **'SQL executed successfully. {count} rows returned.'**
  String aiPanelSqlExecutionSuccess(Object count);

  /// No description provided for @aiPanelSqlGenerationComplete.
  ///
  /// In en, this message translates to:
  /// **'SQL Generation Complete'**
  String get aiPanelSqlGenerationComplete;

  /// No description provided for @aiPanelSqlGenerationCompleteWarning.
  ///
  /// In en, this message translates to:
  /// **'SQL Generation Complete ⚠️'**
  String get aiPanelSqlGenerationCompleteWarning;

  /// No description provided for @aiPanelTaskCompleteDesc.
  ///
  /// In en, this message translates to:
  /// **'Task completed. You can choose to execute or copy the SQL.'**
  String get aiPanelTaskCompleteDesc;

  /// No description provided for @aiPanelDangerousOperationDesc.
  ///
  /// In en, this message translates to:
  /// **'This is a dangerous operation. Please handle with care.'**
  String get aiPanelDangerousOperationDesc;

  /// No description provided for @aiPanelGeneratedSql.
  ///
  /// In en, this message translates to:
  /// **'Generated SQL'**
  String get aiPanelGeneratedSql;

  /// No description provided for @aiPanelDangerous.
  ///
  /// In en, this message translates to:
  /// **'Dangerous'**
  String get aiPanelDangerous;

  /// No description provided for @aiPanelContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get aiPanelContinue;

  /// No description provided for @aiPanelClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get aiPanelClose;

  /// No description provided for @aiPanelCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get aiPanelCopy;

  /// No description provided for @aiPanelExecute.
  ///
  /// In en, this message translates to:
  /// **'Execute'**
  String get aiPanelExecute;

  /// No description provided for @aiPanelConfirmExecuteDangerous.
  ///
  /// In en, this message translates to:
  /// **'Confirm Execute'**
  String get aiPanelConfirmExecuteDangerous;

  /// No description provided for @quickActionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Quick Actions'**
  String get quickActionsTitle;

  /// No description provided for @quickActionsNewTable.
  ///
  /// In en, this message translates to:
  /// **'New Table'**
  String get quickActionsNewTable;

  /// No description provided for @quickActionsNewQuery.
  ///
  /// In en, this message translates to:
  /// **'New Query'**
  String get quickActionsNewQuery;

  /// No description provided for @quickActionsAiAssistant.
  ///
  /// In en, this message translates to:
  /// **'AI Assistant'**
  String get quickActionsAiAssistant;

  /// No description provided for @quickActionsSelectDatabaseFirst.
  ///
  /// In en, this message translates to:
  /// **'Please select a database first'**
  String get quickActionsSelectDatabaseFirst;

  /// No description provided for @resultsTabResults.
  ///
  /// In en, this message translates to:
  /// **'Results'**
  String get resultsTabResults;

  /// No description provided for @resultsTabMessages.
  ///
  /// In en, this message translates to:
  /// **'Messages'**
  String get resultsTabMessages;

  /// No description provided for @resultsTabExecutionPlan.
  ///
  /// In en, this message translates to:
  /// **'Execution Plan'**
  String get resultsTabExecutionPlan;

  /// No description provided for @resultsTabExecutionDetails.
  ///
  /// In en, this message translates to:
  /// **'Execution Details'**
  String get resultsTabExecutionDetails;

  /// No description provided for @resultsSearchBtn.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get resultsSearchBtn;

  /// No description provided for @resultsSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search in results…'**
  String get resultsSearchHint;

  /// No description provided for @resultsSearchNoMatch.
  ///
  /// In en, this message translates to:
  /// **'No rows match \"{query}\"'**
  String resultsSearchNoMatch(Object query);

  /// No description provided for @resultsClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get resultsClear;

  /// No description provided for @resultsSubmit.
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get resultsSubmit;

  /// No description provided for @resultsSearchResults.
  ///
  /// In en, this message translates to:
  /// **'Search Results'**
  String get resultsSearchResults;

  /// No description provided for @resultsViewTable.
  ///
  /// In en, this message translates to:
  /// **'Table'**
  String get resultsViewTable;

  /// No description provided for @resultsViewCard.
  ///
  /// In en, this message translates to:
  /// **'Card'**
  String get resultsViewCard;

  /// No description provided for @resultsViewChart.
  ///
  /// In en, this message translates to:
  /// **'Chart'**
  String get resultsViewChart;

  /// No description provided for @resultsViewStatistics.
  ///
  /// In en, this message translates to:
  /// **'Statistics'**
  String get resultsViewStatistics;

  /// No description provided for @paginationShowing.
  ///
  /// In en, this message translates to:
  /// **'Showing'**
  String get paginationShowing;

  /// No description provided for @paginationRows.
  ///
  /// In en, this message translates to:
  /// **'of'**
  String get paginationRows;

  /// No description provided for @paginationFirstPage.
  ///
  /// In en, this message translates to:
  /// **'First Page'**
  String get paginationFirstPage;

  /// No description provided for @paginationPreviousPage.
  ///
  /// In en, this message translates to:
  /// **'Previous Page'**
  String get paginationPreviousPage;

  /// No description provided for @paginationNextPage.
  ///
  /// In en, this message translates to:
  /// **'Next Page'**
  String get paginationNextPage;

  /// No description provided for @paginationLastPage.
  ///
  /// In en, this message translates to:
  /// **'Last Page'**
  String get paginationLastPage;

  /// No description provided for @editModeTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Mode'**
  String get editModeTitle;

  /// No description provided for @editModeChanges.
  ///
  /// In en, this message translates to:
  /// **'changes'**
  String get editModeChanges;

  /// No description provided for @editModeHint.
  ///
  /// In en, this message translates to:
  /// **'Double-click to edit | Enter to confirm | Esc to cancel | Tab to switch'**
  String get editModeHint;

  /// No description provided for @resultsNoDataTitle.
  ///
  /// In en, this message translates to:
  /// **'No Results'**
  String get resultsNoDataTitle;

  /// No description provided for @resultsNoDataMessage.
  ///
  /// In en, this message translates to:
  /// **'Results will appear after executing a query'**
  String get resultsNoDataMessage;

  /// No description provided for @resultsNoDataCardMessage.
  ///
  /// In en, this message translates to:
  /// **'Card view will appear after executing a query'**
  String get resultsNoDataCardMessage;

  /// No description provided for @resultsNoDataChartMessage.
  ///
  /// In en, this message translates to:
  /// **'Chart will appear after executing a query'**
  String get resultsNoDataChartMessage;

  /// No description provided for @resultsNoDataStatisticsMessage.
  ///
  /// In en, this message translates to:
  /// **'Statistics will appear after executing a query'**
  String get resultsNoDataStatisticsMessage;

  /// No description provided for @resultsNoDataExecutionPlanMessage.
  ///
  /// In en, this message translates to:
  /// **'Click \'Execution Plan\' button to view query execution plan'**
  String get resultsNoDataExecutionPlanMessage;

  /// No description provided for @statisticsTotalRows.
  ///
  /// In en, this message translates to:
  /// **'Total Rows'**
  String get statisticsTotalRows;

  /// No description provided for @statisticsFieldInfo.
  ///
  /// In en, this message translates to:
  /// **'Field Information'**
  String get statisticsFieldInfo;

  /// No description provided for @statisticsNumeric.
  ///
  /// In en, this message translates to:
  /// **'Numeric'**
  String get statisticsNumeric;

  /// No description provided for @statisticsText.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get statisticsText;

  /// No description provided for @statisticsNumericStats.
  ///
  /// In en, this message translates to:
  /// **'Numeric Statistics'**
  String get statisticsNumericStats;

  /// No description provided for @statisticsCount.
  ///
  /// In en, this message translates to:
  /// **'Count'**
  String get statisticsCount;

  /// No description provided for @statisticsSum.
  ///
  /// In en, this message translates to:
  /// **'Sum'**
  String get statisticsSum;

  /// No description provided for @statisticsAvg.
  ///
  /// In en, this message translates to:
  /// **'Average'**
  String get statisticsAvg;

  /// No description provided for @statisticsMin.
  ///
  /// In en, this message translates to:
  /// **'Minimum'**
  String get statisticsMin;

  /// No description provided for @statisticsMax.
  ///
  /// In en, this message translates to:
  /// **'Maximum'**
  String get statisticsMax;

  /// No description provided for @chartXAxis.
  ///
  /// In en, this message translates to:
  /// **'X Axis'**
  String get chartXAxis;

  /// No description provided for @chartYAxis.
  ///
  /// In en, this message translates to:
  /// **'Y Axis'**
  String get chartYAxis;

  /// No description provided for @chartType.
  ///
  /// In en, this message translates to:
  /// **'Type: '**
  String get chartType;

  /// No description provided for @chartCannotGenerate.
  ///
  /// In en, this message translates to:
  /// **'Cannot generate chart: Please ensure Y-axis field contains numeric data'**
  String get chartCannotGenerate;

  /// No description provided for @messagesQuerySuccess.
  ///
  /// In en, this message translates to:
  /// **'Query successful, returned {rows} rows, {cols} columns'**
  String messagesQuerySuccess(Object cols, Object rows);

  /// No description provided for @messagesExecuteToSeeResults.
  ///
  /// In en, this message translates to:
  /// **'Results info will appear after executing a query'**
  String get messagesExecuteToSeeResults;

  /// No description provided for @sqlPreviewWillExecute.
  ///
  /// In en, this message translates to:
  /// **'Will execute {count} SQL statements on table `{table}`:'**
  String sqlPreviewWillExecute(Object count, Object table);

  /// No description provided for @saveErrorNoTab.
  ///
  /// In en, this message translates to:
  /// **'Cannot save: Current tab does not exist'**
  String get saveErrorNoTab;

  /// No description provided for @saveErrorCannotExtractTable.
  ///
  /// In en, this message translates to:
  /// **'Cannot save: Cannot extract table name from query'**
  String get saveErrorCannotExtractTable;

  /// No description provided for @saveErrorFailed.
  ///
  /// In en, this message translates to:
  /// **'Save failed: {error}'**
  String saveErrorFailed(Object error);

  /// No description provided for @exportSelectFormat.
  ///
  /// In en, this message translates to:
  /// **'Select export format'**
  String get exportSelectFormat;

  /// No description provided for @toolbarExecute.
  ///
  /// In en, this message translates to:
  /// **'Execute'**
  String get toolbarExecute;

  /// No description provided for @toolbarStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get toolbarStop;

  /// No description provided for @toolbarReadOnlyChip.
  ///
  /// In en, this message translates to:
  /// **'Read-only'**
  String get toolbarReadOnlyChip;

  /// No description provided for @toolbarLimitChipTooltip.
  ///
  /// In en, this message translates to:
  /// **'Row limit for this connection (auto LIMIT)'**
  String get toolbarLimitChipTooltip;

  /// No description provided for @toolbarTimeoutChipTooltip.
  ///
  /// In en, this message translates to:
  /// **'Query timeout for this connection'**
  String get toolbarTimeoutChipTooltip;

  /// No description provided for @toolbarChipFollowSettings.
  ///
  /// In en, this message translates to:
  /// **'Follow settings'**
  String get toolbarChipFollowSettings;

  /// No description provided for @toolbarChipOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get toolbarChipOff;

  /// No description provided for @toolbarChipFollowConnection.
  ///
  /// In en, this message translates to:
  /// **'Follow connection'**
  String get toolbarChipFollowConnection;

  /// No description provided for @gridEditBlockedReadOnly.
  ///
  /// In en, this message translates to:
  /// **'This connection is read-only — cell edits are disabled.'**
  String get gridEditBlockedReadOnly;

  /// No description provided for @gridEditBlockedNoTable.
  ///
  /// In en, this message translates to:
  /// **'Cannot infer the target table from this result — cell edits need a single-table query.'**
  String get gridEditBlockedNoTable;

  /// No description provided for @gridEditsCount.
  ///
  /// In en, this message translates to:
  /// **'{count} cell change(s) in {rows} row(s)'**
  String gridEditsCount(Object count, Object rows);

  /// No description provided for @gridCommitButton.
  ///
  /// In en, this message translates to:
  /// **'Commit changes'**
  String get gridCommitButton;

  /// No description provided for @gridDiscardButton.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get gridDiscardButton;

  /// No description provided for @gridCommitSuccess.
  ///
  /// In en, this message translates to:
  /// **'{rows} row(s) written back'**
  String gridCommitSuccess(Object rows);

  /// No description provided for @gridCommitNoPrimaryKey.
  ///
  /// In en, this message translates to:
  /// **'Table {table} has no primary key — cannot write back.'**
  String gridCommitNoPrimaryKey(Object table);

  /// No description provided for @gridCommitFailed.
  ///
  /// In en, this message translates to:
  /// **'Write-back failed: {error}'**
  String gridCommitFailed(Object error);

  /// No description provided for @statusBarReady.
  ///
  /// In en, this message translates to:
  /// **'Ready'**
  String get statusBarReady;

  /// No description provided for @statusBarExecuting.
  ///
  /// In en, this message translates to:
  /// **'Executing'**
  String get statusBarExecuting;

  /// No description provided for @statusBarElapsed.
  ///
  /// In en, this message translates to:
  /// **'Elapsed {duration}'**
  String statusBarElapsed(String duration);

  /// No description provided for @statusBarLineCol.
  ///
  /// In en, this message translates to:
  /// **'Ln {line}, Col {column}'**
  String statusBarLineCol(int line, int column);

  /// No description provided for @executionStatusBarRows.
  ///
  /// In en, this message translates to:
  /// **'{count} rows'**
  String executionStatusBarRows(int count);

  /// No description provided for @executionStatusBarErrorHint.
  ///
  /// In en, this message translates to:
  /// **'Click a result tab to see error details'**
  String get executionStatusBarErrorHint;

  /// No description provided for @toolbarExecutionPlan.
  ///
  /// In en, this message translates to:
  /// **'Execution Plan'**
  String get toolbarExecutionPlan;

  /// No description provided for @toolbarFormat.
  ///
  /// In en, this message translates to:
  /// **'Format'**
  String get toolbarFormat;

  /// No description provided for @toolbarSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get toolbarSave;

  /// No description provided for @splitButton.
  ///
  /// In en, this message translates to:
  /// **'Split Editor'**
  String get splitButton;

  /// No description provided for @horizontalSplit.
  ///
  /// In en, this message translates to:
  /// **'Horizontal Split'**
  String get horizontalSplit;

  /// No description provided for @verticalSplit.
  ///
  /// In en, this message translates to:
  /// **'Vertical Split'**
  String get verticalSplit;

  /// No description provided for @refreshData.
  ///
  /// In en, this message translates to:
  /// **'Refresh Data'**
  String get refreshData;

  /// No description provided for @analyzingDatabasePerformance.
  ///
  /// In en, this message translates to:
  /// **'Analyzing database performance...'**
  String get analyzingDatabasePerformance;

  /// No description provided for @fullTableScanDetected.
  ///
  /// In en, this message translates to:
  /// **'Full Table Scan Detected'**
  String get fullTableScanDetected;

  /// No description provided for @fullTableScanDesc.
  ///
  /// In en, this message translates to:
  /// **'Query uses full table scan (type=ALL), consider adding index on WHERE clause columns'**
  String get fullTableScanDesc;

  /// No description provided for @timeThreshold.
  ///
  /// In en, this message translates to:
  /// **'Time Threshold:'**
  String get timeThreshold;

  /// No description provided for @searchPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Search...'**
  String get searchPlaceholder;

  /// No description provided for @closeBtn.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get closeBtn;

  /// No description provided for @apiSettingsSavedMsg.
  ///
  /// In en, this message translates to:
  /// **'API settings saved'**
  String get apiSettingsSavedMsg;

  /// No description provided for @resultsHeaderExport.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get resultsHeaderExport;

  /// No description provided for @resultsHeaderSearch.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get resultsHeaderSearch;

  /// No description provided for @resultsHeaderClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get resultsHeaderClear;

  /// No description provided for @resultsHeaderSubmit.
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get resultsHeaderSubmit;

  /// No description provided for @connectionStatusConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get connectionStatusConnected;

  /// No description provided for @connectionStatusNotConnected.
  ///
  /// In en, this message translates to:
  /// **'Not Connected'**
  String get connectionStatusNotConnected;

  /// No description provided for @selectConnection.
  ///
  /// In en, this message translates to:
  /// **'Select Connection...'**
  String get selectConnection;

  /// No description provided for @selectDatabase.
  ///
  /// In en, this message translates to:
  /// **'Select Database'**
  String get selectDatabase;

  /// No description provided for @aiQuickActionOptimizeSql.
  ///
  /// In en, this message translates to:
  /// **'Optimize SQL'**
  String get aiQuickActionOptimizeSql;

  /// No description provided for @aiQuickActionExplainQuery.
  ///
  /// In en, this message translates to:
  /// **'Explain Query'**
  String get aiQuickActionExplainQuery;

  /// No description provided for @aiQuickActionGenerateInsert.
  ///
  /// In en, this message translates to:
  /// **'Generate INSERT'**
  String get aiQuickActionGenerateInsert;

  /// No description provided for @aiQuickActionGenerateUpdate.
  ///
  /// In en, this message translates to:
  /// **'Generate UPDATE'**
  String get aiQuickActionGenerateUpdate;

  /// No description provided for @aiQuickActionGenerateDelete.
  ///
  /// In en, this message translates to:
  /// **'Generate DELETE'**
  String get aiQuickActionGenerateDelete;

  /// No description provided for @aiQuickActionCreateTable.
  ///
  /// In en, this message translates to:
  /// **'Create Table Statement'**
  String get aiQuickActionCreateTable;

  /// No description provided for @aiQuickActionSecurityCheck.
  ///
  /// In en, this message translates to:
  /// **'Security Check'**
  String get aiQuickActionSecurityCheck;

  /// No description provided for @aiQuickActionIndexSuggestion.
  ///
  /// In en, this message translates to:
  /// **'Index Suggestion'**
  String get aiQuickActionIndexSuggestion;

  /// No description provided for @aiQuickActionExecutionPlan.
  ///
  /// In en, this message translates to:
  /// **'Execution Plan'**
  String get aiQuickActionExecutionPlan;

  /// No description provided for @aiQuickActionQueryHistory.
  ///
  /// In en, this message translates to:
  /// **'Query History'**
  String get aiQuickActionQueryHistory;

  /// No description provided for @shortcutCategoryQuery.
  ///
  /// In en, this message translates to:
  /// **'Query'**
  String get shortcutCategoryQuery;

  /// No description provided for @queryCancelled.
  ///
  /// In en, this message translates to:
  /// **'Query cancelled'**
  String get queryCancelled;

  /// No description provided for @queryFailed.
  ///
  /// In en, this message translates to:
  /// **'Query failed: {error}'**
  String queryFailed(Object error);

  /// No description provided for @querySuccessWithTime.
  ///
  /// In en, this message translates to:
  /// **'Query successful, returned {count} rows ({time}ms)'**
  String querySuccessWithTime(Object count, Object time);

  /// No description provided for @cancelingQuery.
  ///
  /// In en, this message translates to:
  /// **'Canceling query...'**
  String get cancelingQuery;

  /// No description provided for @cancelQueryFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to cancel query'**
  String get cancelQueryFailed;

  /// No description provided for @confirmCancelTransaction.
  ///
  /// In en, this message translates to:
  /// **'Confirm Cancel Transaction'**
  String get confirmCancelTransaction;

  /// No description provided for @confirmCancelTransactionMessage.
  ///
  /// In en, this message translates to:
  /// **'The current connection has an uncommitted transaction. Canceling the query will disconnect and reconnect, causing the transaction to rollback. Continue?'**
  String get confirmCancelTransactionMessage;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @explainPlanSuccess.
  ///
  /// In en, this message translates to:
  /// **'Explain plan retrieved successfully'**
  String get explainPlanSuccess;

  /// No description provided for @explainPlanFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to get explain plan: {error}'**
  String explainPlanFailed(Object error);

  /// No description provided for @queryEmptyCannotSave.
  ///
  /// In en, this message translates to:
  /// **'The query is empty and cannot be saved'**
  String get queryEmptyCannotSave;

  /// No description provided for @saveQueryTitle.
  ///
  /// In en, this message translates to:
  /// **'Save Query'**
  String get saveQueryTitle;

  /// No description provided for @queryName.
  ///
  /// In en, this message translates to:
  /// **'Query Name'**
  String get queryName;

  /// No description provided for @enterQueryName.
  ///
  /// In en, this message translates to:
  /// **'Enter query name'**
  String get enterQueryName;

  /// No description provided for @saveQueryHint.
  ///
  /// In en, this message translates to:
  /// **'Will be saved to saved queries list (max 20)'**
  String get saveQueryHint;

  /// No description provided for @querySaved.
  ///
  /// In en, this message translates to:
  /// **'Query saved: {name}'**
  String querySaved(Object name);

  /// No description provided for @saveQueryLimitReached.
  ///
  /// In en, this message translates to:
  /// **'Save limit reached (20). Please delete some queries first.'**
  String get saveQueryLimitReached;

  /// No description provided for @savedQueryNameExists.
  ///
  /// In en, this message translates to:
  /// **'Saved query name \"{name}\" already exists for this connection'**
  String savedQueryNameExists(Object name);

  /// No description provided for @sqlFormatted.
  ///
  /// In en, this message translates to:
  /// **'SQL formatted'**
  String get sqlFormatted;

  /// No description provided for @pleaseEnterSqlCode.
  ///
  /// In en, this message translates to:
  /// **'Please enter the SQL code'**
  String get pleaseEnterSqlCode;

  /// No description provided for @noConnectedServer.
  ///
  /// In en, this message translates to:
  /// **'No connected server'**
  String get noConnectedServer;

  /// No description provided for @split2Hint.
  ///
  /// In en, this message translates to:
  /// **'Split 2 - Enter SQL query...'**
  String get split2Hint;

  /// No description provided for @toolbarClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get toolbarClose;

  /// No description provided for @connectedToServer.
  ///
  /// In en, this message translates to:
  /// **'Connected to {serverName}'**
  String connectedToServer(Object serverName);

  /// No description provided for @openTableDataFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to open table data: {error}'**
  String openTableDataFailed(Object error);

  /// No description provided for @queryTable.
  ///
  /// In en, this message translates to:
  /// **'Query {tableName}'**
  String queryTable(Object tableName);

  /// No description provided for @openViewFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to open view: {error}'**
  String openViewFailed(Object error);

  /// No description provided for @queryView.
  ///
  /// In en, this message translates to:
  /// **'Query {viewName}'**
  String queryView(Object viewName);

  /// No description provided for @openProcedureFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to open stored procedure: {error}'**
  String openProcedureFailed(Object error);

  /// No description provided for @callProcedure.
  ///
  /// In en, this message translates to:
  /// **'Call {procName}'**
  String callProcedure(Object procName);

  /// No description provided for @cancelConnection.
  ///
  /// In en, this message translates to:
  /// **'Cancel Connection'**
  String get cancelConnection;

  /// No description provided for @deleteConnectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete Connection'**
  String get deleteConnectionTitle;

  /// No description provided for @deleteConnectionConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete connection \"{serverName}\"?'**
  String deleteConnectionConfirm(Object serverName);

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @createNewTable.
  ///
  /// In en, this message translates to:
  /// **'New Table'**
  String get createNewTable;

  /// No description provided for @erDiagram.
  ///
  /// In en, this message translates to:
  /// **'ER Diagram'**
  String get erDiagram;

  /// No description provided for @properties.
  ///
  /// In en, this message translates to:
  /// **'Properties'**
  String get properties;

  /// No description provided for @exportStructure.
  ///
  /// In en, this message translates to:
  /// **'Export Structure'**
  String get exportStructure;

  /// No description provided for @dropDatabase.
  ///
  /// In en, this message translates to:
  /// **'Drop Database'**
  String get dropDatabase;

  /// Title for the drop database confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Delete Database'**
  String get confirmDeleteDatabase;

  /// Title for the drop table confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Drop Table'**
  String get confirmDropTable;

  /// Label for the type-to-confirm text input field
  ///
  /// In en, this message translates to:
  /// **'Type \"{name}\" to confirm'**
  String typeNameToConfirm(String name);

  /// Warning text in the drop database confirmation dialog
  ///
  /// In en, this message translates to:
  /// **'Database \"{name}\" will be permanently deleted.'**
  String dropDatabaseWarning(String name);

  /// Warning showing count of child objects to be destroyed
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 {type} will be destroyed} other{{count} {type}s will be destroyed}}'**
  String objectCountWarning(int count, String type);

  /// Generic data loss warning in destructive confirmation dialogs
  ///
  /// In en, this message translates to:
  /// **'All data will be lost'**
  String get allDataWillBeLost;

  /// No description provided for @copiedDbStructureToClipboard.
  ///
  /// In en, this message translates to:
  /// **'Copied structure of {dbName} to clipboard'**
  String copiedDbStructureToClipboard(Object dbName);

  /// No description provided for @databaseDeleted.
  ///
  /// In en, this message translates to:
  /// **'Database {dbName} deleted'**
  String databaseDeleted(Object dbName);

  /// No description provided for @browseData.
  ///
  /// In en, this message translates to:
  /// **'Browse Data'**
  String get browseData;

  /// No description provided for @editTable.
  ///
  /// In en, this message translates to:
  /// **'Edit Table'**
  String get editTable;

  /// No description provided for @copyTableName.
  ///
  /// In en, this message translates to:
  /// **'Copy Table Name'**
  String get copyTableName;

  /// No description provided for @copyColumnName.
  ///
  /// In en, this message translates to:
  /// **'Copy Column Name'**
  String get copyColumnName;

  /// No description provided for @copyIndexName.
  ///
  /// In en, this message translates to:
  /// **'Copy Index Name'**
  String get copyIndexName;

  /// No description provided for @dropColumn.
  ///
  /// In en, this message translates to:
  /// **'Drop Column'**
  String get dropColumn;

  /// No description provided for @editIndex.
  ///
  /// In en, this message translates to:
  /// **'Edit Index'**
  String get editIndex;

  /// No description provided for @dropIndex.
  ///
  /// In en, this message translates to:
  /// **'Drop Index'**
  String get dropIndex;

  /// No description provided for @confirmDropColumn.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to drop column \"{column}\" from table \"{table}\"?'**
  String confirmDropColumn(Object column, Object table);

  /// No description provided for @confirmDropIndex.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to drop index \"{index}\"?'**
  String confirmDropIndex(Object index);

  /// No description provided for @columnDropped.
  ///
  /// In en, this message translates to:
  /// **'Column \"{column}\" dropped'**
  String columnDropped(Object column);

  /// No description provided for @indexDropped.
  ///
  /// In en, this message translates to:
  /// **'Index \"{index}\" dropped'**
  String indexDropped(Object index);

  /// No description provided for @dropColumnFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to drop column: {error}'**
  String dropColumnFailed(Object error);

  /// No description provided for @dropIndexFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to drop index: {error}'**
  String dropIndexFailed(Object error);

  /// No description provided for @loadingSchema.
  ///
  /// In en, this message translates to:
  /// **'Loading...'**
  String get loadingSchema;

  /// No description provided for @noColumns.
  ///
  /// In en, this message translates to:
  /// **'No Columns'**
  String get noColumns;

  /// No description provided for @noIndexes.
  ///
  /// In en, this message translates to:
  /// **'No indexes'**
  String get noIndexes;

  /// No description provided for @noProgrammableObjects.
  ///
  /// In en, this message translates to:
  /// **'This database type does not support programmable objects'**
  String get noProgrammableObjects;

  /// No description provided for @exportData.
  ///
  /// In en, this message translates to:
  /// **'Export Data'**
  String get exportData;

  /// No description provided for @dataSync.
  ///
  /// In en, this message translates to:
  /// **'Data Sync'**
  String get dataSync;

  /// No description provided for @rename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get rename;

  /// No description provided for @truncate.
  ///
  /// In en, this message translates to:
  /// **'Truncate'**
  String get truncate;

  /// No description provided for @dropTable.
  ///
  /// In en, this message translates to:
  /// **'Drop Table'**
  String get dropTable;

  /// No description provided for @loadTableStructureFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load table structure: {error}'**
  String loadTableStructureFailed(Object error);

  /// No description provided for @tableNameCopied.
  ///
  /// In en, this message translates to:
  /// **'Table name copied'**
  String get tableNameCopied;

  /// No description provided for @copiedTableDataToClipboard.
  ///
  /// In en, this message translates to:
  /// **'Copied data of {tableName} to clipboard'**
  String copiedTableDataToClipboard(Object tableName);

  /// No description provided for @tableRenamedTo.
  ///
  /// In en, this message translates to:
  /// **'Table renamed to {newName}'**
  String tableRenamedTo(Object newName);

  /// No description provided for @renameFailed.
  ///
  /// In en, this message translates to:
  /// **'Rename failed: {error}'**
  String renameFailed(Object error);

  /// No description provided for @tableTruncated.
  ///
  /// In en, this message translates to:
  /// **'Table {tableName} truncated'**
  String tableTruncated(Object tableName);

  /// No description provided for @truncateFailed.
  ///
  /// In en, this message translates to:
  /// **'Truncate failed: {error}'**
  String truncateFailed(Object error);

  /// No description provided for @tableDeleted.
  ///
  /// In en, this message translates to:
  /// **'Table {tableName} deleted'**
  String tableDeleted(Object tableName);

  /// No description provided for @analyzeTable.
  ///
  /// In en, this message translates to:
  /// **'Analyze Table'**
  String get analyzeTable;

  /// No description provided for @optimizeTable.
  ///
  /// In en, this message translates to:
  /// **'Optimize Table'**
  String get optimizeTable;

  /// No description provided for @checkTable.
  ///
  /// In en, this message translates to:
  /// **'Check Table'**
  String get checkTable;

  /// Title for the confirmation dialog to analyze a table.
  ///
  /// In en, this message translates to:
  /// **'Analyze Table {tableName}'**
  String confirmAnalyzeTable(Object tableName);

  /// Message explaining what ANALYZE TABLE does.
  ///
  /// In en, this message translates to:
  /// **'This will update index statistics for table \"{tableName}\".'**
  String confirmAnalyzeTableMessage(Object tableName);

  /// Title for the confirmation dialog to optimize a table.
  ///
  /// In en, this message translates to:
  /// **'Optimize Table {tableName}'**
  String confirmOptimizeTable(Object tableName);

  /// Message explaining what OPTIMIZE TABLE does.
  ///
  /// In en, this message translates to:
  /// **'This will defragment and reclaim unused space for table \"{tableName}\".'**
  String confirmOptimizeTableMessage(Object tableName);

  /// Title for the confirmation dialog to check a table.
  ///
  /// In en, this message translates to:
  /// **'Check Table {tableName}'**
  String confirmCheckTable(Object tableName);

  /// Message explaining what CHECK TABLE does.
  ///
  /// In en, this message translates to:
  /// **'This will check table \"{tableName}\" for errors.'**
  String confirmCheckTableMessage(Object tableName);

  /// No description provided for @optimizeTableWarning.
  ///
  /// In en, this message translates to:
  /// **'This operation may lock the table and take a long time on large tables.'**
  String get optimizeTableWarning;

  /// No description provided for @analyzeTableResultTitle.
  ///
  /// In en, this message translates to:
  /// **'Analyze Result: {tableName}'**
  String analyzeTableResultTitle(Object tableName);

  /// No description provided for @optimizeTableResultTitle.
  ///
  /// In en, this message translates to:
  /// **'Optimize Result: {tableName}'**
  String optimizeTableResultTitle(Object tableName);

  /// No description provided for @checkTableResultTitle.
  ///
  /// In en, this message translates to:
  /// **'Check Result: {tableName}'**
  String checkTableResultTitle(Object tableName);

  /// No description provided for @maintenanceExecutedSql.
  ///
  /// In en, this message translates to:
  /// **'Executed SQL'**
  String get maintenanceExecutedSql;

  /// No description provided for @maintenanceResult.
  ///
  /// In en, this message translates to:
  /// **'Result'**
  String get maintenanceResult;

  /// No description provided for @maintenanceFailed.
  ///
  /// In en, this message translates to:
  /// **'{operation} failed: {error}'**
  String maintenanceFailed(Object operation, Object error);

  /// No description provided for @tableMaintenance.
  ///
  /// In en, this message translates to:
  /// **'Table Maintenance'**
  String get tableMaintenance;

  /// No description provided for @vacuumTable.
  ///
  /// In en, this message translates to:
  /// **'VACUUM'**
  String get vacuumTable;

  /// No description provided for @vacuumFullTable.
  ///
  /// In en, this message translates to:
  /// **'VACUUM FULL'**
  String get vacuumFullTable;

  /// No description provided for @analyzeTablePg.
  ///
  /// In en, this message translates to:
  /// **'ANALYZE'**
  String get analyzeTablePg;

  /// No description provided for @reindexTable.
  ///
  /// In en, this message translates to:
  /// **'REINDEX'**
  String get reindexTable;

  /// No description provided for @reindexTableConcurrently.
  ///
  /// In en, this message translates to:
  /// **'REINDEX CONCURRENTLY'**
  String get reindexTableConcurrently;

  /// No description provided for @clusterTable.
  ///
  /// In en, this message translates to:
  /// **'CLUSTER'**
  String get clusterTable;

  /// Title for the confirmation dialog to vacuum a PostgreSQL table.
  ///
  /// In en, this message translates to:
  /// **'VACUUM {tableName}'**
  String confirmVacuumTable(Object tableName);

  /// Message explaining what VACUUM does.
  ///
  /// In en, this message translates to:
  /// **'This will reclaim storage occupied by dead tuples in table \"{tableName}\".'**
  String confirmVacuumTableMessage(Object tableName);

  /// Title for the confirmation dialog to VACUUM FULL a table.
  ///
  /// In en, this message translates to:
  /// **'VACUUM FULL {tableName}'**
  String confirmVacuumFullTable(Object tableName);

  /// No description provided for @confirmVacuumFullTableMessage.
  ///
  /// In en, this message translates to:
  /// **'This will completely rewrite table \"{tableName}\" and reclaim all free space back to the OS.'**
  String confirmVacuumFullTableMessage(Object tableName);

  /// Title for the confirmation dialog to analyze a PostgreSQL table.
  ///
  /// In en, this message translates to:
  /// **'ANALYZE {tableName}'**
  String confirmAnalyzeTablePg(Object tableName);

  /// No description provided for @confirmAnalyzeTablePgMessage.
  ///
  /// In en, this message translates to:
  /// **'This will update query planner statistics for table \"{tableName}\".'**
  String confirmAnalyzeTablePgMessage(Object tableName);

  /// Title for the confirmation dialog to REINDEX a table.
  ///
  /// In en, this message translates to:
  /// **'REINDEX {tableName}'**
  String confirmReindexTable(Object tableName);

  /// No description provided for @confirmReindexTableMessage.
  ///
  /// In en, this message translates to:
  /// **'This will rebuild all indexes on table \"{tableName}\" to eliminate bloat.'**
  String confirmReindexTableMessage(Object tableName);

  /// Title for the confirmation dialog to REINDEX CONCURRENTLY.
  ///
  /// In en, this message translates to:
  /// **'REINDEX CONCURRENTLY {tableName}'**
  String confirmReindexConcurrentlyTable(Object tableName);

  /// No description provided for @confirmReindexConcurrentlyTableMessage.
  ///
  /// In en, this message translates to:
  /// **'This will rebuild all indexes on table \"{tableName}\" without blocking writes.'**
  String confirmReindexConcurrentlyTableMessage(Object tableName);

  /// Title for the confirmation dialog to CLUSTER a table.
  ///
  /// In en, this message translates to:
  /// **'CLUSTER {tableName}'**
  String confirmClusterTable(Object tableName);

  /// No description provided for @confirmClusterTableMessage.
  ///
  /// In en, this message translates to:
  /// **'This will physically reorder table \"{tableName}\" based on its primary index.'**
  String confirmClusterTableMessage(Object tableName);

  /// No description provided for @vacuumFullWarning.
  ///
  /// In en, this message translates to:
  /// **'This operation acquires an ACCESS EXCLUSIVE lock and blocks all concurrent reads/writes.'**
  String get vacuumFullWarning;

  /// No description provided for @reindexWarning.
  ///
  /// In en, this message translates to:
  /// **'This operation blocks writes to the table until the index rebuild completes.'**
  String get reindexWarning;

  /// No description provided for @clusterWarning.
  ///
  /// In en, this message translates to:
  /// **'This operation acquires an ACCESS EXCLUSIVE lock and rewrites the entire table.'**
  String get clusterWarning;

  /// No description provided for @vacuumTableResultTitle.
  ///
  /// In en, this message translates to:
  /// **'VACUUM Result: {tableName}'**
  String vacuumTableResultTitle(Object tableName);

  /// No description provided for @vacuumFullTableResultTitle.
  ///
  /// In en, this message translates to:
  /// **'VACUUM FULL Result: {tableName}'**
  String vacuumFullTableResultTitle(Object tableName);

  /// No description provided for @analyzeTablePgResultTitle.
  ///
  /// In en, this message translates to:
  /// **'ANALYZE Result: {tableName}'**
  String analyzeTablePgResultTitle(Object tableName);

  /// No description provided for @reindexTableResultTitle.
  ///
  /// In en, this message translates to:
  /// **'REINDEX Result: {tableName}'**
  String reindexTableResultTitle(Object tableName);

  /// No description provided for @reindexConcurrentlyTableResultTitle.
  ///
  /// In en, this message translates to:
  /// **'REINDEX CONCURRENTLY Result: {tableName}'**
  String reindexConcurrentlyTableResultTitle(Object tableName);

  /// No description provided for @clusterTableResultTitle.
  ///
  /// In en, this message translates to:
  /// **'CLUSTER Result: {tableName}'**
  String clusterTableResultTitle(Object tableName);

  /// No description provided for @indexTypeNormal.
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get indexTypeNormal;

  /// No description provided for @indexTypeUnique.
  ///
  /// In en, this message translates to:
  /// **'Unique'**
  String get indexTypeUnique;

  /// No description provided for @hintIndexColumns.
  ///
  /// In en, this message translates to:
  /// **'e.g.: id, name'**
  String get hintIndexColumns;

  /// No description provided for @pleaseDefineAtLeastOneColumn.
  ///
  /// In en, this message translates to:
  /// **'Please define at least one column'**
  String get pleaseDefineAtLeastOneColumn;

  /// No description provided for @tableCreated.
  ///
  /// In en, this message translates to:
  /// **'Table {tableName} created successfully'**
  String tableCreated(Object tableName);

  /// No description provided for @createFailed.
  ///
  /// In en, this message translates to:
  /// **'Create failed: {error}'**
  String createFailed(Object error);

  /// No description provided for @tableModified.
  ///
  /// In en, this message translates to:
  /// **'Table modified successfully'**
  String get tableModified;

  /// No description provided for @modifyFailed.
  ///
  /// In en, this message translates to:
  /// **'Modify failed: {error}'**
  String modifyFailed(Object error);

  /// No description provided for @noInformation.
  ///
  /// In en, this message translates to:
  /// **'No information'**
  String get noInformation;

  /// No description provided for @truncateTableData.
  ///
  /// In en, this message translates to:
  /// **'Truncate Table Data'**
  String get truncateTableData;

  /// No description provided for @menuCut.
  ///
  /// In en, this message translates to:
  /// **'Cut'**
  String get menuCut;

  /// No description provided for @menuCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get menuCopy;

  /// No description provided for @menuPaste.
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get menuPaste;

  /// No description provided for @menuSelectAll.
  ///
  /// In en, this message translates to:
  /// **'Select All'**
  String get menuSelectAll;

  /// No description provided for @menuFormatSql.
  ///
  /// In en, this message translates to:
  /// **'Format SQL'**
  String get menuFormatSql;

  /// No description provided for @menuExecuteQuery.
  ///
  /// In en, this message translates to:
  /// **'Execute Query'**
  String get menuExecuteQuery;

  /// No description provided for @commandNewConnection.
  ///
  /// In en, this message translates to:
  /// **'New Connection'**
  String get commandNewConnection;

  /// No description provided for @commandNewTab.
  ///
  /// In en, this message translates to:
  /// **'New Tab'**
  String get commandNewTab;

  /// No description provided for @commandExecuteQuery.
  ///
  /// In en, this message translates to:
  /// **'Execute Query'**
  String get commandExecuteQuery;

  /// No description provided for @commandFormatSql.
  ///
  /// In en, this message translates to:
  /// **'Format SQL'**
  String get commandFormatSql;

  /// No description provided for @commandToggleAiPanel.
  ///
  /// In en, this message translates to:
  /// **'Toggle AI Panel'**
  String get commandToggleAiPanel;

  /// No description provided for @commandQueryHistory.
  ///
  /// In en, this message translates to:
  /// **'Query History'**
  String get commandQueryHistory;

  /// No description provided for @commandShortcuts.
  ///
  /// In en, this message translates to:
  /// **'Keyboard Shortcuts'**
  String get commandShortcuts;

  /// No description provided for @commandSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get commandSettings;

  /// No description provided for @commandCategoryHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get commandCategoryHistory;

  /// No description provided for @commandCategoryHelp.
  ///
  /// In en, this message translates to:
  /// **'Help'**
  String get commandCategoryHelp;

  /// No description provided for @commandDescNewConnection.
  ///
  /// In en, this message translates to:
  /// **'Create a new database connection'**
  String get commandDescNewConnection;

  /// No description provided for @commandDescNewTab.
  ///
  /// In en, this message translates to:
  /// **'Create a new query tab'**
  String get commandDescNewTab;

  /// No description provided for @commandDescExecuteQuery.
  ///
  /// In en, this message translates to:
  /// **'Run current SQL query'**
  String get commandDescExecuteQuery;

  /// No description provided for @commandDescFormatSql.
  ///
  /// In en, this message translates to:
  /// **'Format SQL code'**
  String get commandDescFormatSql;

  /// No description provided for @commandDescToggleSidebar.
  ///
  /// In en, this message translates to:
  /// **'Show or hide sidebar'**
  String get commandDescToggleSidebar;

  /// No description provided for @commandDescToggleAiPanel.
  ///
  /// In en, this message translates to:
  /// **'Show or hide AI assistant panel'**
  String get commandDescToggleAiPanel;

  /// No description provided for @commandDescQueryHistory.
  ///
  /// In en, this message translates to:
  /// **'View execution history'**
  String get commandDescQueryHistory;

  /// No description provided for @commandDescShortcuts.
  ///
  /// In en, this message translates to:
  /// **'View all keyboard shortcuts'**
  String get commandDescShortcuts;

  /// No description provided for @commandDescSettings.
  ///
  /// In en, this message translates to:
  /// **'Open application settings'**
  String get commandDescSettings;

  /// No description provided for @searchNavigateKeys.
  ///
  /// In en, this message translates to:
  /// **'↑↓/Mouse'**
  String get searchNavigateKeys;

  /// No description provided for @menuConnect.
  ///
  /// In en, this message translates to:
  /// **'Connect'**
  String get menuConnect;

  /// No description provided for @menuCancelConnection.
  ///
  /// In en, this message translates to:
  /// **'Cancel Connection'**
  String get menuCancelConnection;

  /// No description provided for @menuDisconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get menuDisconnect;

  /// No description provided for @menuRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get menuRefresh;

  /// No description provided for @menuEditConnection.
  ///
  /// In en, this message translates to:
  /// **'Edit Connection'**
  String get menuEditConnection;

  /// No description provided for @menuCloneConnection.
  ///
  /// In en, this message translates to:
  /// **'Clone Connection'**
  String get menuCloneConnection;

  /// No description provided for @menuDeleteConnection.
  ///
  /// In en, this message translates to:
  /// **'Delete Connection'**
  String get menuDeleteConnection;

  /// No description provided for @addColumn.
  ///
  /// In en, this message translates to:
  /// **'Add Column'**
  String get addColumn;

  /// No description provided for @addIndex.
  ///
  /// In en, this message translates to:
  /// **'Add Index'**
  String get addIndex;

  /// No description provided for @noIndexesClickToAdd.
  ///
  /// In en, this message translates to:
  /// **'No indexes yet. Click the button above to add one.'**
  String get noIndexesClickToAdd;

  /// No description provided for @formatCSV.
  ///
  /// In en, this message translates to:
  /// **'CSV'**
  String get formatCSV;

  /// No description provided for @formatJSON.
  ///
  /// In en, this message translates to:
  /// **'JSON'**
  String get formatJSON;

  /// No description provided for @formatExcel.
  ///
  /// In en, this message translates to:
  /// **'Excel'**
  String get formatExcel;

  /// No description provided for @formatMarkdown.
  ///
  /// In en, this message translates to:
  /// **'Markdown'**
  String get formatMarkdown;

  /// No description provided for @formatSqlInsert.
  ///
  /// In en, this message translates to:
  /// **'SQL INSERT'**
  String get formatSqlInsert;

  /// No description provided for @formatCSVDesc.
  ///
  /// In en, this message translates to:
  /// **'CSV is a universal spreadsheet format, compatible with Excel, Numbers, Google Sheets, etc.'**
  String get formatCSVDesc;

  /// No description provided for @formatJSONDesc.
  ///
  /// In en, this message translates to:
  /// **'JSON is a structured data format suitable for program reading or API calls.'**
  String get formatJSONDesc;

  /// No description provided for @formatExcelDesc.
  ///
  /// In en, this message translates to:
  /// **'Excel format preserves data types and formatting, suitable for in-depth data analysis.'**
  String get formatExcelDesc;

  /// No description provided for @formatMarkdownDesc.
  ///
  /// In en, this message translates to:
  /// **'Markdown table format is suitable for documentation, reports, or code review.'**
  String get formatMarkdownDesc;

  /// No description provided for @formatSqlInsertDesc.
  ///
  /// In en, this message translates to:
  /// **'SQL INSERT statements can be directly imported into other databases, suitable for data migration.'**
  String get formatSqlInsertDesc;

  /// No description provided for @copiedToClipboard.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get copiedToClipboard;

  /// No description provided for @hintFormatName.
  ///
  /// In en, this message translates to:
  /// **'e.g.: My Format'**
  String get hintFormatName;

  /// No description provided for @hintOptionalDescription.
  ///
  /// In en, this message translates to:
  /// **'Optional description'**
  String get hintOptionalDescription;

  /// No description provided for @formatterSelectPreset.
  ///
  /// In en, this message translates to:
  /// **'Select preset'**
  String get formatterSelectPreset;

  /// No description provided for @formatterFormat.
  ///
  /// In en, this message translates to:
  /// **'Format'**
  String get formatterFormat;

  /// No description provided for @formatterCopyResult.
  ///
  /// In en, this message translates to:
  /// **'Copy result'**
  String get formatterCopyResult;

  /// No description provided for @formatterHintInputSql.
  ///
  /// In en, this message translates to:
  /// **'Enter SQL code here...'**
  String get formatterHintInputSql;

  /// No description provided for @formatterSpace.
  ///
  /// In en, this message translates to:
  /// **'Space'**
  String get formatterSpace;

  /// No description provided for @formatterTab.
  ///
  /// In en, this message translates to:
  /// **'Tab'**
  String get formatterTab;

  /// No description provided for @formatterIndentSize.
  ///
  /// In en, this message translates to:
  /// **'Indent size'**
  String get formatterIndentSize;

  /// No description provided for @formatterMaxLineLength.
  ///
  /// In en, this message translates to:
  /// **'Max line length'**
  String get formatterMaxLineLength;

  /// No description provided for @formatterUppercaseKeywords.
  ///
  /// In en, this message translates to:
  /// **'Uppercase keywords'**
  String get formatterUppercaseKeywords;

  /// No description provided for @formatterAlignKeywords.
  ///
  /// In en, this message translates to:
  /// **'Align keywords'**
  String get formatterAlignKeywords;

  /// No description provided for @formatterPreserveComments.
  ///
  /// In en, this message translates to:
  /// **'Preserve comments'**
  String get formatterPreserveComments;

  /// No description provided for @formatterNewlineBeforeParentheses.
  ///
  /// In en, this message translates to:
  /// **'Newline before parentheses'**
  String get formatterNewlineBeforeParentheses;

  /// No description provided for @formatterCompactMode.
  ///
  /// In en, this message translates to:
  /// **'Compact mode'**
  String get formatterCompactMode;

  /// No description provided for @formatterPosition.
  ///
  /// In en, this message translates to:
  /// **'Position'**
  String get formatterPosition;

  /// No description provided for @formatterEnd.
  ///
  /// In en, this message translates to:
  /// **'End'**
  String get formatterEnd;

  /// No description provided for @formatterStart.
  ///
  /// In en, this message translates to:
  /// **'Start'**
  String get formatterStart;

  /// No description provided for @loadFailed.
  ///
  /// In en, this message translates to:
  /// **'Load failed: {error}'**
  String loadFailed(Object error);

  /// Generic export failure message
  ///
  /// In en, this message translates to:
  /// **'Export failed: {error}'**
  String exportFailed(String error);

  /// No description provided for @timeAgoDays.
  ///
  /// In en, this message translates to:
  /// **'{count} days ago'**
  String timeAgoDays(Object count);

  /// No description provided for @timeAgoHours.
  ///
  /// In en, this message translates to:
  /// **'{count} hours ago'**
  String timeAgoHours(Object count);

  /// No description provided for @timeAgoMinutes.
  ///
  /// In en, this message translates to:
  /// **'{count} minutes ago'**
  String timeAgoMinutes(Object count);

  /// No description provided for @timeAgoJustNow.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get timeAgoJustNow;

  /// No description provided for @optimizationFullTableScan.
  ///
  /// In en, this message translates to:
  /// **'Full Table Scan Detected'**
  String get optimizationFullTableScan;

  /// No description provided for @optimizationFullTableScanDesc.
  ///
  /// In en, this message translates to:
  /// **'Query uses full table scan (type=ALL). Consider adding index on WHERE clause columns.'**
  String get optimizationFullTableScanDesc;

  /// No description provided for @optimizationFilesort.
  ///
  /// In en, this message translates to:
  /// **'Filesort'**
  String get optimizationFilesort;

  /// No description provided for @optimizationFilesortDesc.
  ///
  /// In en, this message translates to:
  /// **'Query uses filesort (Using filesort). Consider adding index on ORDER BY columns.'**
  String get optimizationFilesortDesc;

  /// No description provided for @optimizationTemporary.
  ///
  /// In en, this message translates to:
  /// **'Temporary Table'**
  String get optimizationTemporary;

  /// No description provided for @optimizationTemporaryDesc.
  ///
  /// In en, this message translates to:
  /// **'Query uses temporary table (Using temporary). Consider optimizing GROUP BY or DISTINCT queries.'**
  String get optimizationTemporaryDesc;

  /// No description provided for @optimizationLowEfficiency.
  ///
  /// In en, this message translates to:
  /// **'Low Scan Efficiency'**
  String get optimizationLowEfficiency;

  /// No description provided for @optimizationLowEfficiencyDesc.
  ///
  /// In en, this message translates to:
  /// **'Scanned {rowsExamined} rows but only returned {rowsSent} rows. Scan ratio: {ratio}:1'**
  String optimizationLowEfficiencyDesc(
    Object ratio,
    Object rowsExamined,
    Object rowsSent,
  );

  /// No description provided for @optimizationNoIssue.
  ///
  /// In en, this message translates to:
  /// **'No obvious issues found'**
  String get optimizationNoIssue;

  /// No description provided for @optimizationNoIssueDesc.
  ///
  /// In en, this message translates to:
  /// **'Query execution plan looks normal'**
  String get optimizationNoIssueDesc;

  /// No description provided for @optimizationSuggestions.
  ///
  /// In en, this message translates to:
  /// **'Optimization Suggestions'**
  String get optimizationSuggestions;

  /// No description provided for @indexTypeDistribution.
  ///
  /// In en, this message translates to:
  /// **'Index Type Distribution'**
  String get indexTypeDistribution;

  /// No description provided for @noData.
  ///
  /// In en, this message translates to:
  /// **'No data'**
  String get noData;

  /// No description provided for @indexPrimary.
  ///
  /// In en, this message translates to:
  /// **'Primary'**
  String get indexPrimary;

  /// No description provided for @indexUnique.
  ///
  /// In en, this message translates to:
  /// **'Unique'**
  String get indexUnique;

  /// No description provided for @indexNormal.
  ///
  /// In en, this message translates to:
  /// **'Normal'**
  String get indexNormal;

  /// No description provided for @totalIndexes.
  ///
  /// In en, this message translates to:
  /// **'Total Indexes'**
  String get totalIndexes;

  /// No description provided for @indexUsed.
  ///
  /// In en, this message translates to:
  /// **'Used'**
  String get indexUsed;

  /// No description provided for @indexUnused.
  ///
  /// In en, this message translates to:
  /// **'Unused'**
  String get indexUnused;

  /// No description provided for @indexCount.
  ///
  /// In en, this message translates to:
  /// **'{count} indexes'**
  String indexCount(Object count);

  /// No description provided for @columnCardinality.
  ///
  /// In en, this message translates to:
  /// **'Cardinality: {cardinality}'**
  String columnCardinality(Object cardinality);

  /// No description provided for @columnsLabel.
  ///
  /// In en, this message translates to:
  /// **'Columns: {columns}'**
  String columnsLabel(Object columns);

  /// No description provided for @totalTables.
  ///
  /// In en, this message translates to:
  /// **'Total Tables'**
  String get totalTables;

  /// No description provided for @totalRows.
  ///
  /// In en, this message translates to:
  /// **'Total Rows'**
  String get totalRows;

  /// No description provided for @dataSize.
  ///
  /// In en, this message translates to:
  /// **'Data Size'**
  String get dataSize;

  /// No description provided for @indexSize.
  ///
  /// In en, this message translates to:
  /// **'Index Size'**
  String get indexSize;

  /// No description provided for @tableSizeDistribution.
  ///
  /// In en, this message translates to:
  /// **'Table Size Distribution (Top 10)'**
  String get tableSizeDistribution;

  /// No description provided for @tableNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Table Name'**
  String get tableNameLabel;

  /// No description provided for @tableEngineLabel.
  ///
  /// In en, this message translates to:
  /// **'Engine'**
  String get tableEngineLabel;

  /// No description provided for @tableRowCountLabel.
  ///
  /// In en, this message translates to:
  /// **'Rows'**
  String get tableRowCountLabel;

  /// No description provided for @tableDataSizeLabel.
  ///
  /// In en, this message translates to:
  /// **'Data Size'**
  String get tableDataSizeLabel;

  /// No description provided for @tableIndexSizeLabel.
  ///
  /// In en, this message translates to:
  /// **'Index Size'**
  String get tableIndexSizeLabel;

  /// No description provided for @tableTotalSizeLabel.
  ///
  /// In en, this message translates to:
  /// **'Total Size'**
  String get tableTotalSizeLabel;

  /// No description provided for @tableRatioLabel.
  ///
  /// In en, this message translates to:
  /// **'Ratio'**
  String get tableRatioLabel;

  /// No description provided for @databasePerformanceReport.
  ///
  /// In en, this message translates to:
  /// **'Database Performance Report'**
  String get databasePerformanceReport;

  /// No description provided for @databaseLabel.
  ///
  /// In en, this message translates to:
  /// **'Database: {name}'**
  String databaseLabel(Object name);

  /// No description provided for @generatedAtLabel.
  ///
  /// In en, this message translates to:
  /// **'Generated at: {time}'**
  String generatedAtLabel(Object time);

  /// No description provided for @tableCountLabel.
  ///
  /// In en, this message translates to:
  /// **'Tables'**
  String get tableCountLabel;

  /// No description provided for @slowQueryCountLabel.
  ///
  /// In en, this message translates to:
  /// **'Slow Queries'**
  String get slowQueryCountLabel;

  /// No description provided for @suggestionCountLabel.
  ///
  /// In en, this message translates to:
  /// **'Suggestions'**
  String get suggestionCountLabel;

  /// No description provided for @impactLevel.
  ///
  /// In en, this message translates to:
  /// **'Impact: {level}'**
  String impactLevel(Object level);

  /// No description provided for @impactHigh.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get impactHigh;

  /// No description provided for @impactMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium'**
  String get impactMedium;

  /// No description provided for @impactLow.
  ///
  /// In en, this message translates to:
  /// **'Low'**
  String get impactLow;

  /// No description provided for @recommendedAction.
  ///
  /// In en, this message translates to:
  /// **'Recommended Action:'**
  String get recommendedAction;

  /// No description provided for @slowQueryTopN.
  ///
  /// In en, this message translates to:
  /// **'Slow Query Top {count}'**
  String slowQueryTopN(Object count);

  /// No description provided for @largeTableStats.
  ///
  /// In en, this message translates to:
  /// **'Large Table Statistics'**
  String get largeTableStats;

  /// No description provided for @tabRenameTitle.
  ///
  /// In en, this message translates to:
  /// **'Rename Query'**
  String get tabRenameTitle;

  /// No description provided for @tabRenameHint.
  ///
  /// In en, this message translates to:
  /// **'Enter query name'**
  String get tabRenameHint;

  /// No description provided for @tabRename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get tabRename;

  /// No description provided for @tabClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get tabClose;

  /// No description provided for @tabCloseOthers.
  ///
  /// In en, this message translates to:
  /// **'Close Others'**
  String get tabCloseOthers;

  /// No description provided for @tabCloseToRight.
  ///
  /// In en, this message translates to:
  /// **'Close to Right'**
  String get tabCloseToRight;

  /// No description provided for @tabCloseAll.
  ///
  /// In en, this message translates to:
  /// **'Close All'**
  String get tabCloseAll;

  /// No description provided for @tabDuplicate.
  ///
  /// In en, this message translates to:
  /// **'Duplicate Tab'**
  String get tabDuplicate;

  /// No description provided for @tabNewTooltip.
  ///
  /// In en, this message translates to:
  /// **'New Query (Ctrl+T)'**
  String get tabNewTooltip;

  /// No description provided for @tabNewQueryTitle.
  ///
  /// In en, this message translates to:
  /// **'Query {count}'**
  String tabNewQueryTitle(Object count);

  /// No description provided for @confirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get confirm;

  /// No description provided for @copySuffix.
  ///
  /// In en, this message translates to:
  /// **'(Copy)'**
  String get copySuffix;

  /// No description provided for @triggerTitle.
  ///
  /// In en, this message translates to:
  /// **'Triggers'**
  String get triggerTitle;

  /// No description provided for @triggerFailedToLoad.
  ///
  /// In en, this message translates to:
  /// **'Unable to load triggers: {error}'**
  String triggerFailedToLoad(Object error);

  /// No description provided for @triggerFailedToLoadDefinition.
  ///
  /// In en, this message translates to:
  /// **'Unable to load trigger definition'**
  String get triggerFailedToLoadDefinition;

  /// No description provided for @triggerDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete Trigger'**
  String get triggerDeleteTitle;

  /// No description provided for @triggerDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete trigger \"{name}\"?'**
  String triggerDeleteConfirm(Object name);

  /// No description provided for @triggerDeleted.
  ///
  /// In en, this message translates to:
  /// **'Trigger \"{name}\" deleted'**
  String triggerDeleted(Object name);

  /// No description provided for @triggerDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to delete trigger: {error}'**
  String triggerDeleteFailed(Object error);

  /// No description provided for @triggerCannotDisable.
  ///
  /// In en, this message translates to:
  /// **'MySQL triggers cannot be disabled directly. Use Drop to remove.'**
  String get triggerCannotDisable;

  /// No description provided for @triggerShowList.
  ///
  /// In en, this message translates to:
  /// **'Show List'**
  String get triggerShowList;

  /// No description provided for @triggerGroupByTable.
  ///
  /// In en, this message translates to:
  /// **'Group by Table'**
  String get triggerGroupByTable;

  /// No description provided for @triggerSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search triggers...'**
  String get triggerSearchHint;

  /// No description provided for @triggerNoTriggers.
  ///
  /// In en, this message translates to:
  /// **'No triggers found'**
  String get triggerNoTriggers;

  /// No description provided for @triggerCreate.
  ///
  /// In en, this message translates to:
  /// **'Create Trigger'**
  String get triggerCreate;

  /// No description provided for @triggerViewDefinition.
  ///
  /// In en, this message translates to:
  /// **'View Definition'**
  String get triggerViewDefinition;

  /// No description provided for @triggerCopyName.
  ///
  /// In en, this message translates to:
  /// **'Copy Name'**
  String get triggerCopyName;

  /// No description provided for @triggerCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied \"{name}\" to clipboard'**
  String triggerCopied(Object name);

  /// No description provided for @triggerNew.
  ///
  /// In en, this message translates to:
  /// **'New Trigger'**
  String get triggerNew;

  /// No description provided for @triggerDefinition.
  ///
  /// In en, this message translates to:
  /// **'Trigger: {name}'**
  String triggerDefinition(Object name);

  /// No description provided for @formatterSqlFormat.
  ///
  /// In en, this message translates to:
  /// **'SQL Format'**
  String get formatterSqlFormat;

  /// No description provided for @formatterSavePreset.
  ///
  /// In en, this message translates to:
  /// **'Save Preset'**
  String get formatterSavePreset;

  /// No description provided for @formatterPresetName.
  ///
  /// In en, this message translates to:
  /// **'Preset Name'**
  String get formatterPresetName;

  /// No description provided for @formatterCustomPreset.
  ///
  /// In en, this message translates to:
  /// **'Custom Preset'**
  String get formatterCustomPreset;

  /// No description provided for @formatterBuiltIn.
  ///
  /// In en, this message translates to:
  /// **'Built-in'**
  String get formatterBuiltIn;

  /// No description provided for @formatterSaveAsPreset.
  ///
  /// In en, this message translates to:
  /// **'Save current settings as preset'**
  String get formatterSaveAsPreset;

  /// No description provided for @formatterDeletePreset.
  ///
  /// In en, this message translates to:
  /// **'Delete Preset'**
  String get formatterDeletePreset;

  /// No description provided for @formatterInput.
  ///
  /// In en, this message translates to:
  /// **'Input'**
  String get formatterInput;

  /// No description provided for @formatterOptions.
  ///
  /// In en, this message translates to:
  /// **'Formatting Options'**
  String get formatterOptions;

  /// No description provided for @formatterIndent.
  ///
  /// In en, this message translates to:
  /// **'Indent'**
  String get formatterIndent;

  /// No description provided for @formatterKeywords.
  ///
  /// In en, this message translates to:
  /// **'Keywords'**
  String get formatterKeywords;

  /// No description provided for @formatterCommaStyle.
  ///
  /// In en, this message translates to:
  /// **'Comma Style'**
  String get formatterCommaStyle;

  /// No description provided for @formatterApplyToEditor.
  ///
  /// In en, this message translates to:
  /// **'Apply to Editor'**
  String get formatterApplyToEditor;

  /// No description provided for @filterTitle.
  ///
  /// In en, this message translates to:
  /// **'Filter: {columnName}'**
  String filterTitle(String columnName);

  /// No description provided for @filterEquals.
  ///
  /// In en, this message translates to:
  /// **'equals'**
  String get filterEquals;

  /// No description provided for @filterNotEquals.
  ///
  /// In en, this message translates to:
  /// **'not equals'**
  String get filterNotEquals;

  /// No description provided for @filterContains.
  ///
  /// In en, this message translates to:
  /// **'contains'**
  String get filterContains;

  /// No description provided for @filterNotContains.
  ///
  /// In en, this message translates to:
  /// **'not contains'**
  String get filterNotContains;

  /// No description provided for @filterGreaterThan.
  ///
  /// In en, this message translates to:
  /// **'greater than'**
  String get filterGreaterThan;

  /// No description provided for @filterLessThan.
  ///
  /// In en, this message translates to:
  /// **'less than'**
  String get filterLessThan;

  /// No description provided for @filterIsEmpty.
  ///
  /// In en, this message translates to:
  /// **'is empty'**
  String get filterIsEmpty;

  /// No description provided for @filterIsNotEmpty.
  ///
  /// In en, this message translates to:
  /// **'is not empty'**
  String get filterIsNotEmpty;

  /// No description provided for @filterRegex.
  ///
  /// In en, this message translates to:
  /// **'regex'**
  String get filterRegex;

  /// No description provided for @filterValue.
  ///
  /// In en, this message translates to:
  /// **'Value'**
  String get filterValue;

  /// No description provided for @filterEnterValue.
  ///
  /// In en, this message translates to:
  /// **'Enter filter value'**
  String get filterEnterValue;

  /// No description provided for @filterCaseSensitive.
  ///
  /// In en, this message translates to:
  /// **'Case sensitive'**
  String get filterCaseSensitive;

  /// No description provided for @filterTimeFilter.
  ///
  /// In en, this message translates to:
  /// **'Time Filter'**
  String get filterTimeFilter;

  /// No description provided for @filterToday.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get filterToday;

  /// No description provided for @filterLast24Hours.
  ///
  /// In en, this message translates to:
  /// **'Last 24 Hours'**
  String get filterLast24Hours;

  /// No description provided for @filterLast7Days.
  ///
  /// In en, this message translates to:
  /// **'Last 7 Days'**
  String get filterLast7Days;

  /// No description provided for @filterLast30Days.
  ///
  /// In en, this message translates to:
  /// **'Last 30 Days'**
  String get filterLast30Days;

  /// No description provided for @rowCountLabel.
  ///
  /// In en, this message translates to:
  /// **'{count} rows'**
  String rowCountLabel(Object count);

  /// No description provided for @toolbarCodeSnippets.
  ///
  /// In en, this message translates to:
  /// **'Code Snippets (Ctrl+Shift+S)'**
  String get toolbarCodeSnippets;

  /// No description provided for @toolbarCloseSplit.
  ///
  /// In en, this message translates to:
  /// **'Close Split'**
  String get toolbarCloseSplit;

  /// No description provided for @editorHintText.
  ///
  /// In en, this message translates to:
  /// **'Enter SQL query... (Ctrl+Space for autocomplete, F5/Ctrl+Enter to execute)'**
  String get editorHintText;

  /// No description provided for @editorHintTextMongodb.
  ///
  /// In en, this message translates to:
  /// **'Enter MongoDB query... (F5/Ctrl+Enter to execute)'**
  String get editorHintTextMongodb;

  /// No description provided for @editorHintTextRedis.
  ///
  /// In en, this message translates to:
  /// **'Enter Redis command... (F5/Ctrl+Enter to execute)'**
  String get editorHintTextRedis;

  /// No description provided for @allStatementsSuccess.
  ///
  /// In en, this message translates to:
  /// **'All {count} statements executed successfully ({time}ms)'**
  String allStatementsSuccess(int count, int time);

  /// No description provided for @statementsPartialSuccess.
  ///
  /// In en, this message translates to:
  /// **'{success}/{total} statements succeeded, {failed} failed ({time}ms)'**
  String statementsPartialSuccess(int success, int total, int failed, int time);

  /// No description provided for @statementsAllSuccess.
  ///
  /// In en, this message translates to:
  /// **'{count} statements executed successfully'**
  String statementsAllSuccess(int count);

  /// No description provided for @statementsPartialSuccessShort.
  ///
  /// In en, this message translates to:
  /// **'{success}/{total} succeeded, {failed} failed'**
  String statementsPartialSuccessShort(int success, int total, int failed);

  /// No description provided for @aiPanelCustomModel.
  ///
  /// In en, this message translates to:
  /// **'Custom Model'**
  String get aiPanelCustomModel;

  /// No description provided for @aiPanelBookmarks.
  ///
  /// In en, this message translates to:
  /// **'Bookmarks'**
  String get aiPanelBookmarks;

  /// No description provided for @aiPanelScrollToMessageDeveloping.
  ///
  /// In en, this message translates to:
  /// **'Scroll to message feature is under development'**
  String get aiPanelScrollToMessageDeveloping;

  /// No description provided for @aiPanelBranchConversationCreated.
  ///
  /// In en, this message translates to:
  /// **'Branch conversation created'**
  String get aiPanelBranchConversationCreated;

  /// No description provided for @aiPanelNoConnections.
  ///
  /// In en, this message translates to:
  /// **'No connections yet. Create one to get started.'**
  String get aiPanelNoConnections;

  /// No description provided for @aiPanelConversationList.
  ///
  /// In en, this message translates to:
  /// **'Conversation List'**
  String get aiPanelConversationList;

  /// No description provided for @aiPanelSelectConnection.
  ///
  /// In en, this message translates to:
  /// **'Select Connection'**
  String get aiPanelSelectConnection;

  /// No description provided for @aiPanelNoConnection.
  ///
  /// In en, this message translates to:
  /// **'No Connection'**
  String get aiPanelNoConnection;

  /// No description provided for @aiPanelSelectDatabaseFirst.
  ///
  /// In en, this message translates to:
  /// **'Please select a connection first'**
  String get aiPanelSelectDatabaseFirst;

  /// No description provided for @aiPanelSelectDatabase.
  ///
  /// In en, this message translates to:
  /// **'Select Database'**
  String get aiPanelSelectDatabase;

  /// No description provided for @aiPanelAllDatabases.
  ///
  /// In en, this message translates to:
  /// **'All Databases'**
  String get aiPanelAllDatabases;

  /// No description provided for @aiPanelConnectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Connection failed'**
  String get aiPanelConnectionFailed;

  /// No description provided for @aiPanelUnknownError.
  ///
  /// In en, this message translates to:
  /// **'Unknown error'**
  String get aiPanelUnknownError;

  /// No description provided for @aiPanelLoadDatabasesFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to load databases'**
  String get aiPanelLoadDatabasesFailed;

  /// No description provided for @aiPanelDangerousOperation.
  ///
  /// In en, this message translates to:
  /// **'Dangerous Operation'**
  String get aiPanelDangerousOperation;

  /// No description provided for @aiPanelOptimizeSql.
  ///
  /// In en, this message translates to:
  /// **'Optimize SQL'**
  String get aiPanelOptimizeSql;

  /// No description provided for @aiPanelSecurityAnalysis.
  ///
  /// In en, this message translates to:
  /// **'Security Analysis'**
  String get aiPanelSecurityAnalysis;

  /// No description provided for @aiPanelExecutionPlan.
  ///
  /// In en, this message translates to:
  /// **'Execution Plan'**
  String get aiPanelExecutionPlan;

  /// No description provided for @aiPanelIndexSuggestions.
  ///
  /// In en, this message translates to:
  /// **'Index Suggestions'**
  String get aiPanelIndexSuggestions;

  /// No description provided for @aiPanelInputHint.
  ///
  /// In en, this message translates to:
  /// **'Ask a question about your database, e.g., \"How can I optimize this query?\"'**
  String get aiPanelInputHint;

  /// No description provided for @aiPanelStop.
  ///
  /// In en, this message translates to:
  /// **'Stop'**
  String get aiPanelStop;

  /// No description provided for @aiPanelSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get aiPanelSend;

  /// No description provided for @aiPanelSelectConnectionFirst.
  ///
  /// In en, this message translates to:
  /// **'Please select a connection from the dropdown above first.'**
  String get aiPanelSelectConnectionFirst;

  /// No description provided for @aiPanelConnectionNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'Connection \"{name}\" is not connected or unavailable. Please connect to it first.'**
  String aiPanelConnectionNotAvailable(Object name);

  /// No description provided for @aiPanelTable.
  ///
  /// In en, this message translates to:
  /// **'Table'**
  String get aiPanelTable;

  /// No description provided for @aiPanelDangerousOperationBadge.
  ///
  /// In en, this message translates to:
  /// **'Dangerous Operation'**
  String get aiPanelDangerousOperationBadge;

  /// No description provided for @aiPanelThinkingProcess.
  ///
  /// In en, this message translates to:
  /// **'Thinking Process'**
  String get aiPanelThinkingProcess;

  /// No description provided for @aiPanelExpandThinking.
  ///
  /// In en, this message translates to:
  /// **'Expand thinking process'**
  String get aiPanelExpandThinking;

  /// No description provided for @aiPanelCollapseThinking.
  ///
  /// In en, this message translates to:
  /// **'Collapse thinking process'**
  String get aiPanelCollapseThinking;

  /// No description provided for @aiPanelRenameSession.
  ///
  /// In en, this message translates to:
  /// **'Rename Session'**
  String get aiPanelRenameSession;

  /// No description provided for @aiPanelSessionTitle.
  ///
  /// In en, this message translates to:
  /// **'Session Title'**
  String get aiPanelSessionTitle;

  /// No description provided for @aiPanelDeleteSession.
  ///
  /// In en, this message translates to:
  /// **'Delete Session'**
  String get aiPanelDeleteSession;

  /// No description provided for @aiPanelDeleteSessionConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete \"{name}\"?'**
  String aiPanelDeleteSessionConfirm(Object name);

  /// No description provided for @aiPanelRename.
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get aiPanelRename;

  /// No description provided for @aiPanelUnarchive.
  ///
  /// In en, this message translates to:
  /// **'Unarchive'**
  String get aiPanelUnarchive;

  /// No description provided for @aiPanelArchive.
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get aiPanelArchive;

  /// No description provided for @aiPanelSessions.
  ///
  /// In en, this message translates to:
  /// **'Sessions'**
  String get aiPanelSessions;

  /// No description provided for @aiPanelSearchSessions.
  ///
  /// In en, this message translates to:
  /// **'Search sessions'**
  String get aiPanelSearchSessions;

  /// No description provided for @aiPanelNoSessions.
  ///
  /// In en, this message translates to:
  /// **'No sessions'**
  String get aiPanelNoSessions;

  /// No description provided for @aiPanelArchivedSessions.
  ///
  /// In en, this message translates to:
  /// **'Archived Sessions ({count})'**
  String aiPanelArchivedSessions(Object count);

  /// No description provided for @aiPanelJustNow.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get aiPanelJustNow;

  /// No description provided for @aiPanelMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} minutes ago'**
  String aiPanelMinutesAgo(Object count);

  /// No description provided for @aiPanelHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} hours ago'**
  String aiPanelHoursAgo(Object count);

  /// No description provided for @aiPanelDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} days ago'**
  String aiPanelDaysAgo(Object count);

  /// No description provided for @aiPanelSelectProvider.
  ///
  /// In en, this message translates to:
  /// **'Select Provider'**
  String get aiPanelSelectProvider;

  /// No description provided for @aiPanelSelectModelCurrent.
  ///
  /// In en, this message translates to:
  /// **'Select Model (Current: {provider})'**
  String aiPanelSelectModelCurrent(Object provider);

  /// No description provided for @aiPanelApiConfigCurrent.
  ///
  /// In en, this message translates to:
  /// **'API Configuration (Current: {provider})'**
  String aiPanelApiConfigCurrent(Object provider);

  /// No description provided for @aiPanelModelProviderMismatch.
  ///
  /// In en, this message translates to:
  /// **'The selected model is not compatible with the current provider'**
  String get aiPanelModelProviderMismatch;

  /// No description provided for @aiPanelAllowSession.
  ///
  /// In en, this message translates to:
  /// **'Allow this session'**
  String get aiPanelAllowSession;

  /// No description provided for @aiPanelNoBookmarks.
  ///
  /// In en, this message translates to:
  /// **'No bookmarks'**
  String get aiPanelNoBookmarks;

  /// No description provided for @aiPanelClickBookmarkIcon.
  ///
  /// In en, this message translates to:
  /// **'Click the bookmark icon on a message to add a bookmark'**
  String get aiPanelClickBookmarkIcon;

  /// No description provided for @aiCmdOptimizeSql.
  ///
  /// In en, this message translates to:
  /// **'Optimize SQL statement'**
  String get aiCmdOptimizeSql;

  /// No description provided for @aiCmdExplainQuery.
  ///
  /// In en, this message translates to:
  /// **'Explain query plan'**
  String get aiCmdExplainQuery;

  /// No description provided for @aiCmdGenerateCrud.
  ///
  /// In en, this message translates to:
  /// **'Generate CRUD statements'**
  String get aiCmdGenerateCrud;

  /// No description provided for @aiCmdAnalyzeTable.
  ///
  /// In en, this message translates to:
  /// **'Analyze table structure'**
  String get aiCmdAnalyzeTable;

  /// No description provided for @aiCmdShowHistory.
  ///
  /// In en, this message translates to:
  /// **'View query history'**
  String get aiCmdShowHistory;

  /// No description provided for @aiCmdShowBookmarks.
  ///
  /// In en, this message translates to:
  /// **'View bookmarks'**
  String get aiCmdShowBookmarks;

  /// No description provided for @aiCmdBranchConversation.
  ///
  /// In en, this message translates to:
  /// **'Create branch conversation'**
  String get aiCmdBranchConversation;

  /// No description provided for @aiCmdListDatabases.
  ///
  /// In en, this message translates to:
  /// **'List all databases'**
  String get aiCmdListDatabases;

  /// No description provided for @aiCmdListTables.
  ///
  /// In en, this message translates to:
  /// **'List all tables'**
  String get aiCmdListTables;

  /// No description provided for @settingsThemeMode.
  ///
  /// In en, this message translates to:
  /// **'Theme Mode'**
  String get settingsThemeMode;

  /// No description provided for @settingsThemeColor.
  ///
  /// In en, this message translates to:
  /// **'Accent Color'**
  String get settingsThemeColor;

  /// No description provided for @settingsSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsSystem;

  /// No description provided for @settingsPreview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get settingsPreview;

  /// No description provided for @settingsPrimaryButton.
  ///
  /// In en, this message translates to:
  /// **'Primary Button'**
  String get settingsPrimaryButton;

  /// No description provided for @settingsSecondaryButton.
  ///
  /// In en, this message translates to:
  /// **'Secondary Button'**
  String get settingsSecondaryButton;

  /// No description provided for @settingsApply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get settingsApply;

  /// No description provided for @colorBlue.
  ///
  /// In en, this message translates to:
  /// **'Blue'**
  String get colorBlue;

  /// No description provided for @colorPurple.
  ///
  /// In en, this message translates to:
  /// **'Purple'**
  String get colorPurple;

  /// No description provided for @colorGreen.
  ///
  /// In en, this message translates to:
  /// **'Green'**
  String get colorGreen;

  /// No description provided for @colorOrange.
  ///
  /// In en, this message translates to:
  /// **'Orange'**
  String get colorOrange;

  /// No description provided for @colorRed.
  ///
  /// In en, this message translates to:
  /// **'Red'**
  String get colorRed;

  /// No description provided for @colorCyan.
  ///
  /// In en, this message translates to:
  /// **'Cyan'**
  String get colorCyan;

  /// No description provided for @colorPink.
  ///
  /// In en, this message translates to:
  /// **'Pink'**
  String get colorPink;

  /// No description provided for @colorYellow.
  ///
  /// In en, this message translates to:
  /// **'Yellow'**
  String get colorYellow;

  /// No description provided for @aiChatPageTitle.
  ///
  /// In en, this message translates to:
  /// **'AI Assistant'**
  String get aiChatPageTitle;

  /// No description provided for @messageLabelYou.
  ///
  /// In en, this message translates to:
  /// **'You'**
  String get messageLabelYou;

  /// No description provided for @messageLabelAi.
  ///
  /// In en, this message translates to:
  /// **'AI'**
  String get messageLabelAi;

  /// No description provided for @messageStatusSending.
  ///
  /// In en, this message translates to:
  /// **'Sending'**
  String get messageStatusSending;

  /// No description provided for @messageStatusGenerating.
  ///
  /// In en, this message translates to:
  /// **'Generating'**
  String get messageStatusGenerating;

  /// No description provided for @messageStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get messageStatusFailed;

  /// No description provided for @messageStatusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get messageStatusCancelled;

  /// No description provided for @messageStatusError.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get messageStatusError;

  /// No description provided for @messageStatusThinking.
  ///
  /// In en, this message translates to:
  /// **'Thinking'**
  String get messageStatusThinking;

  /// Input token count
  ///
  /// In en, this message translates to:
  /// **'Input {count}'**
  String tokenUsagePrompt(int count);

  /// Output token count
  ///
  /// In en, this message translates to:
  /// **'Output {count}'**
  String tokenUsageCompletion(int count);

  /// Total token count
  ///
  /// In en, this message translates to:
  /// **'Total {count}'**
  String tokenUsageTotal(int count);

  /// Session-level token usage summary
  ///
  /// In en, this message translates to:
  /// **'Session: Input {promptTokens} · Output {completionTokens} · Total {totalTokens}'**
  String sessionTokenUsage(
    int promptTokens,
    int completionTokens,
    int totalTokens,
  );

  /// No description provided for @messageActionRegenerate.
  ///
  /// In en, this message translates to:
  /// **'Regenerate'**
  String get messageActionRegenerate;

  /// No description provided for @tooltipCopyCode.
  ///
  /// In en, this message translates to:
  /// **'Copy code'**
  String get tooltipCopyCode;

  /// No description provided for @tooltipExecuteCode.
  ///
  /// In en, this message translates to:
  /// **'Execute code'**
  String get tooltipExecuteCode;

  /// No description provided for @messageCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get messageCopied;

  /// No description provided for @toolCallTitle.
  ///
  /// In en, this message translates to:
  /// **'Tool: {name}'**
  String toolCallTitle(String name);

  /// No description provided for @toolResultTitle.
  ///
  /// In en, this message translates to:
  /// **'Result: {name}'**
  String toolResultTitle(String name);

  /// No description provided for @toolCallCompleted.
  ///
  /// In en, this message translates to:
  /// **'Called and completed'**
  String get toolCallCompleted;

  /// No description provided for @toolParamLabel.
  ///
  /// In en, this message translates to:
  /// **'Parameters'**
  String get toolParamLabel;

  /// No description provided for @toolResultLabel.
  ///
  /// In en, this message translates to:
  /// **'Result'**
  String get toolResultLabel;

  /// No description provided for @toolGroupTitle.
  ///
  /// In en, this message translates to:
  /// **'Tool Group'**
  String get toolGroupTitle;

  /// No description provided for @toolGroupSummary.
  ///
  /// In en, this message translates to:
  /// **'Executed {count} tools'**
  String toolGroupSummary(int count);

  /// No description provided for @toolGroupItemTitle.
  ///
  /// In en, this message translates to:
  /// **'Tool {index}: {name}'**
  String toolGroupItemTitle(int index, String name);

  /// No description provided for @toolNoParams.
  ///
  /// In en, this message translates to:
  /// **'No parameters'**
  String get toolNoParams;

  /// No description provided for @aiWelcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'AI Database Assistant'**
  String get aiWelcomeTitle;

  /// No description provided for @aiWelcomeDescription.
  ///
  /// In en, this message translates to:
  /// **'I can help you write SQL, optimize queries, analyze table structures, check security issues, or answer any database-related questions.'**
  String get aiWelcomeDescription;

  /// No description provided for @aiConnectedTo.
  ///
  /// In en, this message translates to:
  /// **'Connected: {name}'**
  String aiConnectedTo(String name);

  /// No description provided for @aiExampleSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Try asking me'**
  String get aiExampleSectionTitle;

  /// No description provided for @aiQuickActionsSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Quick Actions'**
  String get aiQuickActionsSectionTitle;

  /// No description provided for @aiTipQuickSend.
  ///
  /// In en, this message translates to:
  /// **'Ctrl + Enter to send'**
  String get aiTipQuickSend;

  /// No description provided for @aiTipSlashCommands.
  ///
  /// In en, this message translates to:
  /// **'Type / to see all commands'**
  String get aiTipSlashCommands;

  /// No description provided for @aiExampleQuestion1.
  ///
  /// In en, this message translates to:
  /// **'Optimize the performance of this query'**
  String get aiExampleQuestion1;

  /// No description provided for @aiExampleQuestion2.
  ///
  /// In en, this message translates to:
  /// **'Analyze the current table structure'**
  String get aiExampleQuestion2;

  /// No description provided for @aiExampleQuestion3.
  ///
  /// In en, this message translates to:
  /// **'Check the security of this SQL'**
  String get aiExampleQuestion3;

  /// No description provided for @errorApiKeyRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter an API Key first'**
  String get errorApiKeyRequired;

  /// No description provided for @errorBaseUrlRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter a Base URL first'**
  String get errorBaseUrlRequired;

  /// No description provided for @errorFetchModelsFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to fetch model list: {error}'**
  String errorFetchModelsFailed(String error);

  /// No description provided for @tooltipRefreshModels.
  ///
  /// In en, this message translates to:
  /// **'Refresh model list'**
  String get tooltipRefreshModels;

  /// No description provided for @labelCustomModelInput.
  ///
  /// In en, this message translates to:
  /// **'Enter model name manually'**
  String get labelCustomModelInput;

  /// No description provided for @tooltipAddModel.
  ///
  /// In en, this message translates to:
  /// **'Add model'**
  String get tooltipAddModel;

  /// No description provided for @hintFetchOrInputModel.
  ///
  /// In en, this message translates to:
  /// **'Click refresh to fetch or enter model name manually'**
  String get hintFetchOrInputModel;

  /// No description provided for @hintFetchModels.
  ///
  /// In en, this message translates to:
  /// **'Click refresh to fetch model list'**
  String get hintFetchModels;

  /// No description provided for @errorSelectModelRequired.
  ///
  /// In en, this message translates to:
  /// **'Please select or enter a model'**
  String get errorSelectModelRequired;

  /// No description provided for @errorSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Save failed: {error}'**
  String errorSaveFailed(String error);

  /// No description provided for @connErrorWithMessage.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String connErrorWithMessage(String error);

  /// No description provided for @connSearchSnippetsHint.
  ///
  /// In en, this message translates to:
  /// **'Search snippets...'**
  String get connSearchSnippetsHint;

  /// No description provided for @connPreview.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get connPreview;

  /// No description provided for @connInsert.
  ///
  /// In en, this message translates to:
  /// **'Insert'**
  String get connInsert;

  /// No description provided for @connApply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get connApply;

  /// No description provided for @connClearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear All'**
  String get connClearAll;

  /// No description provided for @connSaveConnectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to save connection: {error}'**
  String connSaveConnectionFailed(String error);

  /// No description provided for @connDeleteConnectionFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to delete connection: {error}'**
  String connDeleteConnectionFailed(String error);

  /// No description provided for @connCreateStatement.
  ///
  /// In en, this message translates to:
  /// **'Create Statement'**
  String get connCreateStatement;

  /// No description provided for @connCreateStatementCopied.
  ///
  /// In en, this message translates to:
  /// **'Create statement copied'**
  String get connCreateStatementCopied;

  /// No description provided for @connCopyCreateStatement.
  ///
  /// In en, this message translates to:
  /// **'Copy Create Statement'**
  String get connCopyCreateStatement;

  /// No description provided for @connDeleteDatabase.
  ///
  /// In en, this message translates to:
  /// **'Delete Database'**
  String get connDeleteDatabase;

  /// No description provided for @connCopiedToClipboard.
  ///
  /// In en, this message translates to:
  /// **'Copied to clipboard'**
  String get connCopiedToClipboard;

  /// No description provided for @connCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get connCopy;

  /// No description provided for @connExportFeatureSetup.
  ///
  /// In en, this message translates to:
  /// **'Export feature requires additional setup'**
  String get connExportFeatureSetup;

  /// No description provided for @connExportFailed.
  ///
  /// In en, this message translates to:
  /// **'Export failed: {error}'**
  String connExportFailed(String error);

  /// No description provided for @erDiagramExportSuccess.
  ///
  /// In en, this message translates to:
  /// **'Diagram saved to {path}'**
  String erDiagramExportSuccess(String path);

  /// No description provided for @erDiagramExportNoCanvas.
  ///
  /// In en, this message translates to:
  /// **'No diagram to export. Load a schema first.'**
  String get erDiagramExportNoCanvas;

  /// No description provided for @erDiagramExportEncodeFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to encode PNG. Please try again.'**
  String get erDiagramExportEncodeFailed;

  /// No description provided for @connCopiedTableName.
  ///
  /// In en, this message translates to:
  /// **'Copied: {tableName}'**
  String connCopiedTableName(String tableName);

  /// No description provided for @connRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get connRetry;

  /// No description provided for @connReportIssue.
  ///
  /// In en, this message translates to:
  /// **'Report Issue'**
  String get connReportIssue;

  /// No description provided for @connEnterTableName.
  ///
  /// In en, this message translates to:
  /// **'Enter table name'**
  String get connEnterTableName;

  /// No description provided for @connParameterName.
  ///
  /// In en, this message translates to:
  /// **'Parameter name'**
  String get connParameterName;

  /// No description provided for @connClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get connClear;

  /// No description provided for @connCharset.
  ///
  /// In en, this message translates to:
  /// **'Charset'**
  String get connCharset;

  /// No description provided for @connComment.
  ///
  /// In en, this message translates to:
  /// **'Comment'**
  String get connComment;

  /// No description provided for @connName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get connName;

  /// No description provided for @connDefault.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get connDefault;

  /// No description provided for @connIndexName.
  ///
  /// In en, this message translates to:
  /// **'Index Name'**
  String get connIndexName;

  /// No description provided for @connTruncate.
  ///
  /// In en, this message translates to:
  /// **'Truncate'**
  String get connTruncate;

  /// No description provided for @dlgProcedureUpdated.
  ///
  /// In en, this message translates to:
  /// **'Stored procedure/function updated successfully'**
  String get dlgProcedureUpdated;

  /// No description provided for @dlgProcedureCreated.
  ///
  /// In en, this message translates to:
  /// **'Stored procedure/function created successfully'**
  String get dlgProcedureCreated;

  /// No description provided for @dlgOperationFailed.
  ///
  /// In en, this message translates to:
  /// **'Operation failed: {error}'**
  String dlgOperationFailed(String error);

  /// No description provided for @dlgType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get dlgType;

  /// No description provided for @dlgProcedureType.
  ///
  /// In en, this message translates to:
  /// **'Procedure (PROCEDURE)'**
  String get dlgProcedureType;

  /// No description provided for @dlgFunctionType.
  ///
  /// In en, this message translates to:
  /// **'Function (FUNCTION)'**
  String get dlgFunctionType;

  /// No description provided for @dlgReturnType.
  ///
  /// In en, this message translates to:
  /// **'Return Type'**
  String get dlgReturnType;

  /// No description provided for @dlgEnterSqlHint.
  ///
  /// In en, this message translates to:
  /// **'Enter SQL code...'**
  String get dlgEnterSqlHint;

  /// No description provided for @dlgExecutionFailed.
  ///
  /// In en, this message translates to:
  /// **'Execution failed: {error}'**
  String dlgExecutionFailed(String error);

  /// No description provided for @dlgExecute.
  ///
  /// In en, this message translates to:
  /// **'Execute'**
  String get dlgExecute;

  /// No description provided for @dlgEnterValue.
  ///
  /// In en, this message translates to:
  /// **'Enter value'**
  String get dlgEnterValue;

  /// No description provided for @dlgCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get dlgCopied;

  /// No description provided for @dlgNoHistory.
  ///
  /// In en, this message translates to:
  /// **'No history yet'**
  String get dlgNoHistory;

  /// No description provided for @dlgConfirmDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Confirm Delete'**
  String get dlgConfirmDeleteTitle;

  /// No description provided for @dlgConfirmDeleteHistoryMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this history record?\n\n{sql}'**
  String dlgConfirmDeleteHistoryMessage(String sql);

  /// No description provided for @dlgTestSyntax.
  ///
  /// In en, this message translates to:
  /// **'Test Syntax'**
  String get dlgTestSyntax;

  /// No description provided for @dlgSyntaxError.
  ///
  /// In en, this message translates to:
  /// **'Syntax error: {message}'**
  String dlgSyntaxError(String message);

  /// No description provided for @dlgSyntaxLooksGood.
  ///
  /// In en, this message translates to:
  /// **'Syntax looks good!'**
  String get dlgSyntaxLooksGood;

  /// No description provided for @dlgEnterTriggerName.
  ///
  /// In en, this message translates to:
  /// **'Enter trigger name'**
  String get dlgEnterTriggerName;

  /// No description provided for @dlgEnterVariableValue.
  ///
  /// In en, this message translates to:
  /// **'Enter {variable}'**
  String dlgEnterVariableValue(String variable);

  /// No description provided for @molChooseFromGallery.
  ///
  /// In en, this message translates to:
  /// **'Choose from Gallery'**
  String get molChooseFromGallery;

  /// No description provided for @molTakePhoto.
  ///
  /// In en, this message translates to:
  /// **'Take Photo'**
  String get molTakePhoto;

  /// No description provided for @molPickImageFailed.
  ///
  /// In en, this message translates to:
  /// **'Unable to pick image: {error}'**
  String molPickImageFailed(String error);

  /// No description provided for @molSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get molSend;

  /// No description provided for @svcExportSuccess.
  ///
  /// In en, this message translates to:
  /// **'File exported: {result}'**
  String svcExportSuccess(String result);

  /// No description provided for @svcExportFailed.
  ///
  /// In en, this message translates to:
  /// **'Export failed: {error}'**
  String svcExportFailed(String error);

  /// No description provided for @scrInitFailed.
  ///
  /// In en, this message translates to:
  /// **'Initialization failed: {error}'**
  String scrInitFailed(String error);

  /// No description provided for @smartImportTitle.
  ///
  /// In en, this message translates to:
  /// **'AI Smart Import'**
  String get smartImportTitle;

  /// No description provided for @smartImportSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Automatically analyze file structure and import to database'**
  String get smartImportSubtitle;

  /// No description provided for @smartImportClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get smartImportClose;

  /// No description provided for @smartImportTarget.
  ///
  /// In en, this message translates to:
  /// **'Import Target'**
  String get smartImportTarget;

  /// No description provided for @smartImportSelectedTable.
  ///
  /// In en, this message translates to:
  /// **'Selected table: {table}'**
  String smartImportSelectedTable(String table);

  /// No description provided for @smartImportAutoInfer.
  ///
  /// In en, this message translates to:
  /// **'No table selected, AI will auto-infer'**
  String get smartImportAutoInfer;

  /// No description provided for @smartImportLoadTables.
  ///
  /// In en, this message translates to:
  /// **'Loading table list...'**
  String get smartImportLoadTables;

  /// No description provided for @smartImportTableHint.
  ///
  /// In en, this message translates to:
  /// **'Search or enter table name (leave empty for AI inference)'**
  String get smartImportTableHint;

  /// No description provided for @smartImportStepSelectFile.
  ///
  /// In en, this message translates to:
  /// **'Select File'**
  String get smartImportStepSelectFile;

  /// No description provided for @smartImportStepAnalyze.
  ///
  /// In en, this message translates to:
  /// **'Analyze'**
  String get smartImportStepAnalyze;

  /// No description provided for @smartImportStepImport.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get smartImportStepImport;

  /// No description provided for @smartImportStepComplete.
  ///
  /// In en, this message translates to:
  /// **'Complete'**
  String get smartImportStepComplete;

  /// No description provided for @smartImportSelectFileTitle.
  ///
  /// In en, this message translates to:
  /// **'Select file to import'**
  String get smartImportSelectFileTitle;

  /// No description provided for @smartImportSelectFileHint.
  ///
  /// In en, this message translates to:
  /// **'Click to select CSV or JSON file'**
  String get smartImportSelectFileHint;

  /// No description provided for @smartImportReselectFile.
  ///
  /// In en, this message translates to:
  /// **'Click to reselect'**
  String get smartImportReselectFile;

  /// No description provided for @smartImportSupportedFormats.
  ///
  /// In en, this message translates to:
  /// **'Supported formats: CSV, TSV, JSON, JSON Lines'**
  String get smartImportSupportedFormats;

  /// No description provided for @smartImportAnalyzing.
  ///
  /// In en, this message translates to:
  /// **'Analyzing file structure...'**
  String get smartImportAnalyzing;

  /// No description provided for @smartImportTableNotFound.
  ///
  /// In en, this message translates to:
  /// **'Target table does not exist'**
  String get smartImportTableNotFound;

  /// No description provided for @smartImportTableNotFoundMessage.
  ///
  /// In en, this message translates to:
  /// **'Table \"{table}\" does not exist in the current database.'**
  String smartImportTableNotFoundMessage(String table);

  /// No description provided for @smartImportCreateTableHint.
  ///
  /// In en, this message translates to:
  /// **'Please execute the following CREATE TABLE statement in the SQL editor first, then reopen Smart Import.'**
  String get smartImportCreateTableHint;

  /// No description provided for @smartImportSuggestedSQL.
  ///
  /// In en, this message translates to:
  /// **'Suggested CREATE TABLE statement'**
  String get smartImportSuggestedSQL;

  /// No description provided for @smartImportCopySQL.
  ///
  /// In en, this message translates to:
  /// **'Copy SQL'**
  String get smartImportCopySQL;

  /// No description provided for @smartImportSQLCopied.
  ///
  /// In en, this message translates to:
  /// **'SQL copied to clipboard'**
  String get smartImportSQLCopied;

  /// No description provided for @smartImportImporting.
  ///
  /// In en, this message translates to:
  /// **'Importing data...'**
  String get smartImportImporting;

  /// No description provided for @smartImportImported.
  ///
  /// In en, this message translates to:
  /// **'Imported'**
  String get smartImportImported;

  /// No description provided for @smartImportTotalRecords.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get smartImportTotalRecords;

  /// No description provided for @smartImportFailedRecords.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get smartImportFailedRecords;

  /// No description provided for @smartImportProgress.
  ///
  /// In en, this message translates to:
  /// **'Progress'**
  String get smartImportProgress;

  /// No description provided for @smartImportImportComplete.
  ///
  /// In en, this message translates to:
  /// **'Import Complete'**
  String get smartImportImportComplete;

  /// No description provided for @smartImportTargetTable.
  ///
  /// In en, this message translates to:
  /// **'Target Table'**
  String get smartImportTargetTable;

  /// No description provided for @smartImportSuccessRows.
  ///
  /// In en, this message translates to:
  /// **'Successfully imported'**
  String get smartImportSuccessRows;

  /// No description provided for @smartImportFailedRows.
  ///
  /// In en, this message translates to:
  /// **'Failed to import'**
  String get smartImportFailedRows;

  /// No description provided for @smartImportTotalRows.
  ///
  /// In en, this message translates to:
  /// **'Total rows in table'**
  String get smartImportTotalRows;

  /// No description provided for @smartImportImportFailed.
  ///
  /// In en, this message translates to:
  /// **'Import Failed'**
  String get smartImportImportFailed;

  /// No description provided for @smartImportFilePreview.
  ///
  /// In en, this message translates to:
  /// **'File Preview'**
  String get smartImportFilePreview;

  /// No description provided for @smartImportSampleData.
  ///
  /// In en, this message translates to:
  /// **'Sample data (first 3 rows)'**
  String get smartImportSampleData;

  /// No description provided for @smartImportLogs.
  ///
  /// In en, this message translates to:
  /// **'Import Logs'**
  String get smartImportLogs;

  /// No description provided for @smartImportClearLogs.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get smartImportClearLogs;

  /// No description provided for @smartImportReimport.
  ///
  /// In en, this message translates to:
  /// **'Re-import'**
  String get smartImportReimport;

  /// No description provided for @smartImportStartAnalysis.
  ///
  /// In en, this message translates to:
  /// **'Start Analysis'**
  String get smartImportStartAnalysis;

  /// No description provided for @smartImportStartImport.
  ///
  /// In en, this message translates to:
  /// **'Start Import'**
  String get smartImportStartImport;

  /// No description provided for @smartImportCancelImport.
  ///
  /// In en, this message translates to:
  /// **'Cancel Import'**
  String get smartImportCancelImport;

  /// No description provided for @smartImportUserCancelled.
  ///
  /// In en, this message translates to:
  /// **'User cancelled import'**
  String get smartImportUserCancelled;

  /// No description provided for @smartImportFileSelected.
  ///
  /// In en, this message translates to:
  /// **'File selected: {name}'**
  String smartImportFileSelected(String name);

  /// No description provided for @smartImportAnalysisComplete.
  ///
  /// In en, this message translates to:
  /// **'Analysis complete. Format: {format}, Encoding: {encoding}, Fields: {fields}'**
  String smartImportAnalysisComplete(
    String format,
    String encoding,
    String fields,
  );

  /// No description provided for @smartImportEstimatedRows.
  ///
  /// In en, this message translates to:
  /// **'Estimated total rows: ~{rows}'**
  String smartImportEstimatedRows(String rows);

  /// No description provided for @smartImportUsingSelectedTable.
  ///
  /// In en, this message translates to:
  /// **'Using selected table: {table}'**
  String smartImportUsingSelectedTable(String table);

  /// No description provided for @smartImportCheckTableExists.
  ///
  /// In en, this message translates to:
  /// **'Checking if target table exists...'**
  String get smartImportCheckTableExists;

  /// No description provided for @smartImportTableExists.
  ///
  /// In en, this message translates to:
  /// **'Table \"{table}\" exists with {count} rows'**
  String smartImportTableExists(String table, String count);

  /// No description provided for @smartImportTableNotExists.
  ///
  /// In en, this message translates to:
  /// **'Table \"{table}\" does not exist. Please create table first.'**
  String smartImportTableNotExists(String table);

  /// No description provided for @smartImportAiInferringTable.
  ///
  /// In en, this message translates to:
  /// **'AI inferring table name...'**
  String get smartImportAiInferringTable;

  /// No description provided for @smartImportAiSuggestedTable.
  ///
  /// In en, this message translates to:
  /// **'AI suggested table name: {name}'**
  String smartImportAiSuggestedTable(String name);

  /// No description provided for @smartImportDoNotImport.
  ///
  /// In en, this message translates to:
  /// **'Do not import'**
  String get smartImportDoNotImport;

  /// No description provided for @smartImportTaskDescription.
  ///
  /// In en, this message translates to:
  /// **'Import {count} to {table}'**
  String smartImportTaskDescription(int count, String table);

  /// No description provided for @smartImportStartImporting.
  ///
  /// In en, this message translates to:
  /// **'Starting data import to table \"{table}\"...'**
  String smartImportStartImporting(String table);

  /// No description provided for @smartImportImportResult.
  ///
  /// In en, this message translates to:
  /// **'Import complete! Success: {imported} rows, Failed: {failed} rows'**
  String smartImportImportResult(String imported, String failed);

  /// No description provided for @smartImportQueryRowCount.
  ///
  /// In en, this message translates to:
  /// **'Querying total row count...'**
  String get smartImportQueryRowCount;

  /// No description provided for @smartImportTableTotalRows.
  ///
  /// In en, this message translates to:
  /// **'Table \"{table}\" now has {count} rows'**
  String smartImportTableTotalRows(String table, String count);

  /// No description provided for @smartImportQueryCountFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to query row count: {error}'**
  String smartImportQueryCountFailed(String error);

  /// No description provided for @smartImportImportError.
  ///
  /// In en, this message translates to:
  /// **'Import failed: {error}'**
  String smartImportImportError(String error);

  /// No description provided for @smartImportCopySuccess.
  ///
  /// In en, this message translates to:
  /// **'SQL copied to clipboard'**
  String get smartImportCopySuccess;

  /// No description provided for @smartImportRows.
  ///
  /// In en, this message translates to:
  /// **'{count} rows'**
  String smartImportRows(String count);

  /// No description provided for @smartImportAiModel.
  ///
  /// In en, this message translates to:
  /// **'AI Model'**
  String get smartImportAiModel;

  /// No description provided for @aiPanelFullscreen.
  ///
  /// In en, this message translates to:
  /// **'Fullscreen'**
  String get aiPanelFullscreen;

  /// No description provided for @aiPanelExitFullscreen.
  ///
  /// In en, this message translates to:
  /// **'Exit Fullscreen'**
  String get aiPanelExitFullscreen;

  /// No description provided for @aiPanelOpenInNewQuery.
  ///
  /// In en, this message translates to:
  /// **'Opened in new query'**
  String get aiPanelOpenInNewQuery;

  /// No description provided for @aiPanelInsertStatementsGenerated.
  ///
  /// In en, this message translates to:
  /// **'AI has generated {count} INSERT statements, ready to insert into table [{tableName}].'**
  String aiPanelInsertStatementsGenerated(int count, String tableName);

  /// No description provided for @aiPanelSqlPreviewTitle.
  ///
  /// In en, this message translates to:
  /// **'SQL Preview (first 3):'**
  String get aiPanelSqlPreviewTitle;

  /// No description provided for @aiPanelMoreStatements.
  ///
  /// In en, this message translates to:
  /// **'... and {count} more statements'**
  String aiPanelMoreStatements(int count);

  /// No description provided for @aiAgentToolCallLimitReached.
  ///
  /// In en, this message translates to:
  /// **'AI assistant has reached the tool call limit ({count} times). Please simplify your question or proceed step by step.'**
  String aiAgentToolCallLimitReached(int count);

  /// No description provided for @aiAgentMaxIterationsReached.
  ///
  /// In en, this message translates to:
  /// **'Agent reached maximum iterations and could not complete the conversation.'**
  String get aiAgentMaxIterationsReached;

  /// No description provided for @aiAgentDuplicateQuery.
  ///
  /// In en, this message translates to:
  /// **'This query has already been executed. Please answer directly based on the existing results without repeating the query.'**
  String get aiAgentDuplicateQuery;

  /// No description provided for @aiAgentToolExecutionFailed.
  ///
  /// In en, this message translates to:
  /// **'Tool execution failed: {error}'**
  String aiAgentToolExecutionFailed(String error);

  /// No description provided for @aiAgentUnknownTool.
  ///
  /// In en, this message translates to:
  /// **'Unknown tool: {name}'**
  String aiAgentUnknownTool(String name);

  /// No description provided for @aiContextCurrentDatabase.
  ///
  /// In en, this message translates to:
  /// **'Current database: {name}'**
  String aiContextCurrentDatabase(String name);

  /// No description provided for @aiContextCurrentTable.
  ///
  /// In en, this message translates to:
  /// **'Current table: {name}'**
  String aiContextCurrentTable(String name);

  /// No description provided for @aiContextRecentQueries.
  ///
  /// In en, this message translates to:
  /// **'Recent queries: {queries}'**
  String aiContextRecentQueries(String queries);

  /// No description provided for @aiContextGoalSummary.
  ///
  /// In en, this message translates to:
  /// **'Current session goal summary: {summary}'**
  String aiContextGoalSummary(String summary);

  /// No description provided for @taskPanelTitle.
  ///
  /// In en, this message translates to:
  /// **'Tasks'**
  String get taskPanelTitle;

  /// No description provided for @taskPanelEmpty.
  ///
  /// In en, this message translates to:
  /// **'No tasks'**
  String get taskPanelEmpty;

  /// No description provided for @taskPanelEmptyDesc.
  ///
  /// In en, this message translates to:
  /// **'Import or export operations will appear here'**
  String get taskPanelEmptyDesc;

  /// No description provided for @taskPanelClearCompleted.
  ///
  /// In en, this message translates to:
  /// **'Clear completed'**
  String get taskPanelClearCompleted;

  /// No description provided for @taskPanelStatusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get taskPanelStatusPending;

  /// No description provided for @taskPanelStatusRunning.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get taskPanelStatusRunning;

  /// No description provided for @taskPanelStatusPaused.
  ///
  /// In en, this message translates to:
  /// **'Paused'**
  String get taskPanelStatusPaused;

  /// No description provided for @taskPanelStatusCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get taskPanelStatusCompleted;

  /// No description provided for @taskPanelStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get taskPanelStatusFailed;

  /// No description provided for @taskPanelStatusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get taskPanelStatusCancelled;

  /// No description provided for @taskTypeImport.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get taskTypeImport;

  /// No description provided for @taskTypeExport.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get taskTypeExport;

  /// No description provided for @taskTypeQuery.
  ///
  /// In en, this message translates to:
  /// **'Query'**
  String get taskTypeQuery;

  /// No description provided for @taskActionCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get taskActionCancel;

  /// No description provided for @taskActionRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get taskActionRetry;

  /// No description provided for @taskActionRemove.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get taskActionRemove;

  /// No description provided for @taskActionOpenFolder.
  ///
  /// In en, this message translates to:
  /// **'Open folder'**
  String get taskActionOpenFolder;

  /// No description provided for @taskCreateExportTitle.
  ///
  /// In en, this message translates to:
  /// **'Create Export Task'**
  String get taskCreateExportTitle;

  /// No description provided for @taskCreateExportFormat.
  ///
  /// In en, this message translates to:
  /// **'Export format'**
  String get taskCreateExportFormat;

  /// No description provided for @taskCreateExportPath.
  ///
  /// In en, this message translates to:
  /// **'Output path'**
  String get taskCreateExportPath;

  /// No description provided for @taskCreateExportPathPlaceholder.
  ///
  /// In en, this message translates to:
  /// **'Click the button on the right to select save location'**
  String get taskCreateExportPathPlaceholder;

  /// No description provided for @taskCreateExportPathSelect.
  ///
  /// In en, this message translates to:
  /// **'Select save location'**
  String get taskCreateExportPathSelect;

  /// No description provided for @taskCreateExportStart.
  ///
  /// In en, this message translates to:
  /// **'Create task'**
  String get taskCreateExportStart;

  /// No description provided for @taskValidationPathRequired.
  ///
  /// In en, this message translates to:
  /// **'Please select an output path'**
  String get taskValidationPathRequired;

  /// No description provided for @taskValidationPathNotWritable.
  ///
  /// In en, this message translates to:
  /// **'Directory is not writable, please choose another location'**
  String get taskValidationPathNotWritable;

  /// No description provided for @taskValidationPathExists.
  ///
  /// In en, this message translates to:
  /// **'File already exists and will be overwritten'**
  String get taskValidationPathExists;

  /// No description provided for @taskStatusBarTasks.
  ///
  /// In en, this message translates to:
  /// **'{count} tasks'**
  String taskStatusBarTasks(int count);

  /// No description provided for @taskStatusBarRunning.
  ///
  /// In en, this message translates to:
  /// **'{count} running'**
  String taskStatusBarRunning(int count);

  /// No description provided for @taskLogInfo.
  ///
  /// In en, this message translates to:
  /// **'Info'**
  String get taskLogInfo;

  /// No description provided for @taskLogWarning.
  ///
  /// In en, this message translates to:
  /// **'Warning'**
  String get taskLogWarning;

  /// No description provided for @taskLogError.
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get taskLogError;

  /// No description provided for @taskLogSuccess.
  ///
  /// In en, this message translates to:
  /// **'Success'**
  String get taskLogSuccess;

  /// No description provided for @taskDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'Task Details'**
  String get taskDetailTitle;

  /// No description provided for @taskDetailBasicInfo.
  ///
  /// In en, this message translates to:
  /// **'Basic Information'**
  String get taskDetailBasicInfo;

  /// No description provided for @taskDetailStatistics.
  ///
  /// In en, this message translates to:
  /// **'Statistics'**
  String get taskDetailStatistics;

  /// No description provided for @taskDetailError.
  ///
  /// In en, this message translates to:
  /// **'Error Message'**
  String get taskDetailError;

  /// No description provided for @taskDetailOutputFile.
  ///
  /// In en, this message translates to:
  /// **'Output File'**
  String get taskDetailOutputFile;

  /// No description provided for @taskDetailLogs.
  ///
  /// In en, this message translates to:
  /// **'Execution Logs'**
  String get taskDetailLogs;

  /// No description provided for @taskDetailCopied.
  ///
  /// In en, this message translates to:
  /// **'Path copied to clipboard'**
  String get taskDetailCopied;

  /// No description provided for @taskPhaseAnalyzing.
  ///
  /// In en, this message translates to:
  /// **'Analyzing...'**
  String get taskPhaseAnalyzing;

  /// No description provided for @taskPhaseQuerying.
  ///
  /// In en, this message translates to:
  /// **'Querying data...'**
  String get taskPhaseQuerying;

  /// No description provided for @taskPhaseFormatting.
  ///
  /// In en, this message translates to:
  /// **'Formatting data...'**
  String get taskPhaseFormatting;

  /// No description provided for @taskPhaseWriting.
  ///
  /// In en, this message translates to:
  /// **'Writing file...'**
  String get taskPhaseWriting;

  /// No description provided for @taskPhaseCompleted.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get taskPhaseCompleted;

  /// No description provided for @aiExportButtonCreate.
  ///
  /// In en, this message translates to:
  /// **'Create Export Task'**
  String get aiExportButtonCreate;

  /// No description provided for @aiExportButtonAnalyzing.
  ///
  /// In en, this message translates to:
  /// **'Analyzing...'**
  String get aiExportButtonAnalyzing;

  /// No description provided for @aiMessageExportAction.
  ///
  /// In en, this message translates to:
  /// **'Export this data'**
  String get aiMessageExportAction;

  /// No description provided for @smartImportCreateTask.
  ///
  /// In en, this message translates to:
  /// **'Create import task in background'**
  String get smartImportCreateTask;

  /// No description provided for @schemaDiffTitle.
  ///
  /// In en, this message translates to:
  /// **'Schema Diff & Sync'**
  String get schemaDiffTitle;

  /// No description provided for @schemaDiffMenuItem.
  ///
  /// In en, this message translates to:
  /// **'Schema Diff & Sync'**
  String get schemaDiffMenuItem;

  /// No description provided for @schemaDiffSource.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get schemaDiffSource;

  /// No description provided for @schemaDiffTarget.
  ///
  /// In en, this message translates to:
  /// **'Target'**
  String get schemaDiffTarget;

  /// No description provided for @schemaDiffCompareButton.
  ///
  /// In en, this message translates to:
  /// **'Compare'**
  String get schemaDiffCompareButton;

  /// No description provided for @schemaDiffSelectDatabases.
  ///
  /// In en, this message translates to:
  /// **'Select source and target databases to compare'**
  String get schemaDiffSelectDatabases;

  /// No description provided for @schemaDiffTabOverview.
  ///
  /// In en, this message translates to:
  /// **'Overview'**
  String get schemaDiffTabOverview;

  /// No description provided for @schemaDiffTabDetails.
  ///
  /// In en, this message translates to:
  /// **'Details'**
  String get schemaDiffTabDetails;

  /// No description provided for @schemaDiffTabSync.
  ///
  /// In en, this message translates to:
  /// **'Sync'**
  String get schemaDiffTabSync;

  /// No description provided for @sidebarColumns.
  ///
  /// In en, this message translates to:
  /// **'Columns'**
  String get sidebarColumns;

  /// No description provided for @sidebarIndexes.
  ///
  /// In en, this message translates to:
  /// **'Indexes'**
  String get sidebarIndexes;

  /// No description provided for @sidebarInsertIntoEditor.
  ///
  /// In en, this message translates to:
  /// **'Insert into editor'**
  String get sidebarInsertIntoEditor;

  /// No description provided for @sidebarForeignKeys.
  ///
  /// In en, this message translates to:
  /// **'Foreign Keys'**
  String get sidebarForeignKeys;

  /// No description provided for @sidebarCopyIndexName.
  ///
  /// In en, this message translates to:
  /// **'Copy index name'**
  String get sidebarCopyIndexName;

  /// No description provided for @sidebarCopyForeignKeyName.
  ///
  /// In en, this message translates to:
  /// **'Copy foreign key name'**
  String get sidebarCopyForeignKeyName;

  /// No description provided for @sidebarCopyName.
  ///
  /// In en, this message translates to:
  /// **'Copy Name'**
  String get sidebarCopyName;

  /// No description provided for @sidebarReadOnlyConnection.
  ///
  /// In en, this message translates to:
  /// **'Read-only connection'**
  String get sidebarReadOnlyConnection;

  /// No description provided for @sidebarCopyColumnName.
  ///
  /// In en, this message translates to:
  /// **'Copy column name'**
  String get sidebarCopyColumnName;

  /// No description provided for @sidebarCopyColumnType.
  ///
  /// In en, this message translates to:
  /// **'Copy column type'**
  String get sidebarCopyColumnType;

  /// No description provided for @sidebarCopyAllColumnNames.
  ///
  /// In en, this message translates to:
  /// **'Copy all column names'**
  String get sidebarCopyAllColumnNames;

  /// No description provided for @sidebarOpenEditorFirst.
  ///
  /// In en, this message translates to:
  /// **'Open a query tab first'**
  String get sidebarOpenEditorFirst;

  /// No description provided for @sidebarEvents.
  ///
  /// In en, this message translates to:
  /// **'Events'**
  String get sidebarEvents;

  /// No description provided for @sidebarProgrammableObjects.
  ///
  /// In en, this message translates to:
  /// **'Programmable Objects'**
  String get sidebarProgrammableObjects;

  /// No description provided for @selectDatabaseHint.
  ///
  /// In en, this message translates to:
  /// **'Double-click a database to view its objects'**
  String get selectDatabaseHint;

  /// No description provided for @workspaceEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No Open Queries'**
  String get workspaceEmptyTitle;

  /// No description provided for @workspaceEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Create a new query tab to get started'**
  String get workspaceEmptyHint;

  /// No description provided for @noSearchResults.
  ///
  /// In en, this message translates to:
  /// **'No matching results'**
  String get noSearchResults;

  /// No description provided for @page.
  ///
  /// In en, this message translates to:
  /// **'Page'**
  String get page;

  /// No description provided for @settingsSubscriptionSettings.
  ///
  /// In en, this message translates to:
  /// **'Subscription'**
  String get settingsSubscriptionSettings;

  /// No description provided for @settingsFreePlan.
  ///
  /// In en, this message translates to:
  /// **'Free'**
  String get settingsFreePlan;

  /// No description provided for @settingsFreePlanDesc.
  ///
  /// In en, this message translates to:
  /// **'You are currently on the Free plan'**
  String get settingsFreePlanDesc;

  /// No description provided for @settingsProActivated.
  ///
  /// In en, this message translates to:
  /// **'Pro Activated'**
  String get settingsProActivated;

  /// No description provided for @settingsProActivatedDesc.
  ///
  /// In en, this message translates to:
  /// **'All Pro features are unlocked'**
  String get settingsProActivatedDesc;

  /// No description provided for @settingsUpgradeToPro.
  ///
  /// In en, this message translates to:
  /// **'Upgrade to Pro'**
  String get settingsUpgradeToPro;

  /// No description provided for @settingsRestorePurchases.
  ///
  /// In en, this message translates to:
  /// **'Restore Purchases'**
  String get settingsRestorePurchases;

  /// No description provided for @purchaseDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Upgrade to Pro'**
  String get purchaseDialogTitle;

  /// No description provided for @purchaseDialogDesc.
  ///
  /// In en, this message translates to:
  /// **'Unlock all premium features with a Pro subscription'**
  String get purchaseDialogDesc;

  /// No description provided for @purchaseDialogNoProducts.
  ///
  /// In en, this message translates to:
  /// **'No products available'**
  String get purchaseDialogNoProducts;

  /// No description provided for @freeAiQuotaExceeded.
  ///
  /// In en, this message translates to:
  /// **'You have used all {count} free AI messages this month. Upgrade to Pro for unlimited AI usage.'**
  String freeAiQuotaExceeded(int count);

  /// No description provided for @freeConnectionLimitReached.
  ///
  /// In en, this message translates to:
  /// **'Free plan supports up to {count} saved connections. Upgrade to Pro for unlimited connections.'**
  String freeConnectionLimitReached(int count);

  /// No description provided for @freeTabLimitReached.
  ///
  /// In en, this message translates to:
  /// **'Free plan supports up to {count} open query tabs. Upgrade to Pro for unlimited tabs.'**
  String freeTabLimitReached(int count);

  /// No description provided for @schemaDiffSyncProFeature.
  ///
  /// In en, this message translates to:
  /// **'Schema Diff sync is a Pro feature. Start a free trial or upgrade to Pro to execute synchronization.'**
  String get schemaDiffSyncProFeature;

  /// No description provided for @tableMetadataComment.
  ///
  /// In en, this message translates to:
  /// **'Comment'**
  String get tableMetadataComment;

  /// No description provided for @tableMetadataRowCount.
  ///
  /// In en, this message translates to:
  /// **'Rows'**
  String get tableMetadataRowCount;

  /// No description provided for @tableMetadataDataSize.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get tableMetadataDataSize;

  /// No description provided for @tableMetadataEngine.
  ///
  /// In en, this message translates to:
  /// **'Engine'**
  String get tableMetadataEngine;

  /// No description provided for @tableMetadataUpdateTime.
  ///
  /// In en, this message translates to:
  /// **'Updated'**
  String get tableMetadataUpdateTime;

  /// No description provided for @resultsTruncatedMessage.
  ///
  /// In en, this message translates to:
  /// **'Results limited to first {count} rows. More data may be available.'**
  String resultsTruncatedMessage(Object count);

  /// No description provided for @settingsQueryLimit.
  ///
  /// In en, this message translates to:
  /// **'Query Limit'**
  String get settingsQueryLimit;

  /// No description provided for @settingsAutoLimitEnabled.
  ///
  /// In en, this message translates to:
  /// **'Auto LIMIT'**
  String get settingsAutoLimitEnabled;

  /// No description provided for @settingsAutoLimitValue.
  ///
  /// In en, this message translates to:
  /// **'Limit Value'**
  String get settingsAutoLimitValue;

  /// No description provided for @sidebarFavorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get sidebarFavorites;

  /// No description provided for @recentTables.
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get recentTables;

  /// No description provided for @dataSyncTitle.
  ///
  /// In en, this message translates to:
  /// **'Data Sync'**
  String get dataSyncTitle;

  /// No description provided for @dataSyncCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get dataSyncCancel;

  /// No description provided for @dataSyncClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get dataSyncClose;

  /// No description provided for @dataSyncRestart.
  ///
  /// In en, this message translates to:
  /// **'Resync'**
  String get dataSyncRestart;

  /// No description provided for @dataSyncStart.
  ///
  /// In en, this message translates to:
  /// **'Start Sync'**
  String get dataSyncStart;

  /// No description provided for @dataSyncExecutionLocation.
  ///
  /// In en, this message translates to:
  /// **'Execution Location'**
  String get dataSyncExecutionLocation;

  /// No description provided for @dataSyncExecutionLocal.
  ///
  /// In en, this message translates to:
  /// **'Local (immediate)'**
  String get dataSyncExecutionLocal;

  /// No description provided for @dataSyncExecutionLocalDesc.
  ///
  /// In en, this message translates to:
  /// **'Run directly from this client. Best for one-off single-table syncs.'**
  String get dataSyncExecutionLocalDesc;

  /// No description provided for @dataSyncExecutionServer.
  ///
  /// In en, this message translates to:
  /// **'Server (background)'**
  String get dataSyncExecutionServer;

  /// No description provided for @dataSyncExecutionServerDesc.
  ///
  /// In en, this message translates to:
  /// **'Submit to the Server for background execution with scheduling. Best for large tables and recurring syncs.'**
  String get dataSyncExecutionServerDesc;

  /// No description provided for @dataSyncServerTaskName.
  ///
  /// In en, this message translates to:
  /// **'Task Name'**
  String get dataSyncServerTaskName;

  /// No description provided for @dataSyncServerTaskNameHint.
  ///
  /// In en, this message translates to:
  /// **'my-daily-sync'**
  String get dataSyncServerTaskNameHint;

  /// No description provided for @dataSyncScheduleImmediate.
  ///
  /// In en, this message translates to:
  /// **'Run once now'**
  String get dataSyncScheduleImmediate;

  /// No description provided for @dataSyncScheduleCron.
  ///
  /// In en, this message translates to:
  /// **'Recurring (cron)'**
  String get dataSyncScheduleCron;

  /// No description provided for @dataSyncCronExpr.
  ///
  /// In en, this message translates to:
  /// **'Cron Expression'**
  String get dataSyncCronExpr;

  /// No description provided for @dataSyncCronExprHelp.
  ///
  /// In en, this message translates to:
  /// **'5-field: minute hour day-of-month month day-of-week (UTC).'**
  String get dataSyncCronExprHelp;

  /// No description provided for @dataSyncCronPresetDaily3am.
  ///
  /// In en, this message translates to:
  /// **'Daily 03:00'**
  String get dataSyncCronPresetDaily3am;

  /// No description provided for @dataSyncCronPresetHourly.
  ///
  /// In en, this message translates to:
  /// **'Hourly'**
  String get dataSyncCronPresetHourly;

  /// No description provided for @dataSyncCronPresetWeekly.
  ///
  /// In en, this message translates to:
  /// **'Weekly (Mon 03:00)'**
  String get dataSyncCronPresetWeekly;

  /// No description provided for @dataSyncServerTaskCreated.
  ///
  /// In en, this message translates to:
  /// **'Server task created: {taskId}'**
  String dataSyncServerTaskCreated(String taskId);

  /// No description provided for @dataSyncServerEntitlementGated.
  ///
  /// In en, this message translates to:
  /// **'Server license is gated. Activate or renew the Server license to use background execution.'**
  String get dataSyncServerEntitlementGated;

  /// No description provided for @dataSyncJoinTables.
  ///
  /// In en, this message translates to:
  /// **'Join Tables (LEFT JOIN)'**
  String get dataSyncJoinTables;

  /// No description provided for @dataSyncAddJoinTable.
  ///
  /// In en, this message translates to:
  /// **'Add join table'**
  String get dataSyncAddJoinTable;

  /// No description provided for @dataSyncJoinTableTitle.
  ///
  /// In en, this message translates to:
  /// **'Join table #{index} ({alias})'**
  String dataSyncJoinTableTitle(int index, String alias);

  /// No description provided for @dataSyncJoinTableRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove this join table'**
  String get dataSyncJoinTableRemove;

  /// No description provided for @dataSyncJoinOn.
  ///
  /// In en, this message translates to:
  /// **'ON condition'**
  String get dataSyncJoinOn;

  /// No description provided for @dataSyncJoinSelectColumns.
  ///
  /// In en, this message translates to:
  /// **'Columns to include'**
  String get dataSyncJoinSelectColumns;

  /// No description provided for @dataSyncViewTasks.
  ///
  /// In en, this message translates to:
  /// **'View tasks'**
  String get dataSyncViewTasks;

  /// No description provided for @dataSyncMenuLabel.
  ///
  /// In en, this message translates to:
  /// **'Data Sync Tasks'**
  String get dataSyncMenuLabel;

  /// No description provided for @dataSyncTaskListTitle.
  ///
  /// In en, this message translates to:
  /// **'Data Sync Tasks'**
  String get dataSyncTaskListTitle;

  /// No description provided for @dataSyncTaskListEmpty.
  ///
  /// In en, this message translates to:
  /// **'No sync tasks yet. Create one from a table\'s right-click menu → Data Sync → Server (background).'**
  String get dataSyncTaskListEmpty;

  /// No description provided for @dataSyncTaskRun.
  ///
  /// In en, this message translates to:
  /// **'Run now'**
  String get dataSyncTaskRun;

  /// No description provided for @dataSyncTaskCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get dataSyncTaskCancel;

  /// No description provided for @dataSyncTaskCancelRequested.
  ///
  /// In en, this message translates to:
  /// **'Cancel requested. The run will stop after the current batch completes.'**
  String get dataSyncTaskCancelRequested;

  /// No description provided for @dataSyncTaskHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get dataSyncTaskHistory;

  /// No description provided for @dataSyncTaskDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get dataSyncTaskDelete;

  /// No description provided for @dataSyncTaskDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this task? This cannot be undone.'**
  String get dataSyncTaskDeleteConfirm;

  /// No description provided for @dataSyncTaskPaused.
  ///
  /// In en, this message translates to:
  /// **'paused'**
  String get dataSyncTaskPaused;

  /// No description provided for @dataSyncTaskNeverRun.
  ///
  /// In en, this message translates to:
  /// **'Never run'**
  String get dataSyncTaskNeverRun;

  /// No description provided for @dataSyncRunProgress.
  ///
  /// In en, this message translates to:
  /// **'{percent}%'**
  String dataSyncRunProgress(int percent);

  /// No description provided for @dataSyncRunRows.
  ///
  /// In en, this message translates to:
  /// **'{processed} / {total} rows'**
  String dataSyncRunRows(int processed, int total);

  /// No description provided for @dataSyncRunRowsOnly.
  ///
  /// In en, this message translates to:
  /// **'{processed} rows'**
  String dataSyncRunRowsOnly(int processed);

  /// No description provided for @dataSyncHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Run history — {name}'**
  String dataSyncHistoryTitle(String name);

  /// No description provided for @dataSyncHistoryDuration.
  ///
  /// In en, this message translates to:
  /// **'{ms} ms'**
  String dataSyncHistoryDuration(int ms);

  /// No description provided for @dataSyncHistoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No runs yet.'**
  String get dataSyncHistoryEmpty;

  /// No description provided for @dataSyncStatusRunning.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get dataSyncStatusRunning;

  /// No description provided for @dataSyncStatusSucceeded.
  ///
  /// In en, this message translates to:
  /// **'Succeeded'**
  String get dataSyncStatusSucceeded;

  /// No description provided for @dataSyncStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'Sync Failed'**
  String get dataSyncStatusFailed;

  /// No description provided for @dataSyncStatusCanceled.
  ///
  /// In en, this message translates to:
  /// **'Canceled'**
  String get dataSyncStatusCanceled;

  /// No description provided for @dataSyncRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get dataSyncRefresh;

  /// No description provided for @dataSyncNotConnected.
  ///
  /// In en, this message translates to:
  /// **'Not connected to a DbMaster server.'**
  String get dataSyncNotConnected;

  /// No description provided for @dataSyncSourceConfig.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get dataSyncSourceConfig;

  /// No description provided for @dataSyncSourceConnection.
  ///
  /// In en, this message translates to:
  /// **'Source Connection'**
  String get dataSyncSourceConnection;

  /// No description provided for @dataSyncSourceDatabase.
  ///
  /// In en, this message translates to:
  /// **'Source Database'**
  String get dataSyncSourceDatabase;

  /// No description provided for @dataSyncSourceTable.
  ///
  /// In en, this message translates to:
  /// **'Source Table'**
  String get dataSyncSourceTable;

  /// No description provided for @dataSyncTargetConfig.
  ///
  /// In en, this message translates to:
  /// **'Target'**
  String get dataSyncTargetConfig;

  /// No description provided for @dataSyncTargetConnection.
  ///
  /// In en, this message translates to:
  /// **'Target Connection'**
  String get dataSyncTargetConnection;

  /// No description provided for @dataSyncTargetDatabase.
  ///
  /// In en, this message translates to:
  /// **'Target Database'**
  String get dataSyncTargetDatabase;

  /// No description provided for @dataSyncTargetTable.
  ///
  /// In en, this message translates to:
  /// **'Target Table'**
  String get dataSyncTargetTable;

  /// No description provided for @dataSyncSegmentConfig.
  ///
  /// In en, this message translates to:
  /// **'Segment'**
  String get dataSyncSegmentConfig;

  /// No description provided for @dataSyncSegmentStrategy.
  ///
  /// In en, this message translates to:
  /// **'Strategy'**
  String get dataSyncSegmentStrategy;

  /// No description provided for @dataSyncSegmentTypeNumeric.
  ///
  /// In en, this message translates to:
  /// **'Numeric'**
  String get dataSyncSegmentTypeNumeric;

  /// No description provided for @dataSyncSegmentTypeTime.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get dataSyncSegmentTypeTime;

  /// No description provided for @dataSyncSegmentField.
  ///
  /// In en, this message translates to:
  /// **'Field'**
  String get dataSyncSegmentField;

  /// No description provided for @dataSyncTimeUnit.
  ///
  /// In en, this message translates to:
  /// **'Unit'**
  String get dataSyncTimeUnit;

  /// No description provided for @dataSyncTimeUnitMinute.
  ///
  /// In en, this message translates to:
  /// **'Minute'**
  String get dataSyncTimeUnitMinute;

  /// No description provided for @dataSyncTimeUnitHour.
  ///
  /// In en, this message translates to:
  /// **'Hour'**
  String get dataSyncTimeUnitHour;

  /// No description provided for @dataSyncTimeUnitDay.
  ///
  /// In en, this message translates to:
  /// **'Day'**
  String get dataSyncTimeUnitDay;

  /// No description provided for @dataSyncIntervalValue.
  ///
  /// In en, this message translates to:
  /// **'Interval'**
  String get dataSyncIntervalValue;

  /// No description provided for @dataSyncSegmentSize.
  ///
  /// In en, this message translates to:
  /// **'Segment Size'**
  String get dataSyncSegmentSize;

  /// No description provided for @dataSyncAdvancedOptions.
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get dataSyncAdvancedOptions;

  /// No description provided for @dataSyncPageSize.
  ///
  /// In en, this message translates to:
  /// **'Page Size'**
  String get dataSyncPageSize;

  /// No description provided for @dataSyncTargetStrategy.
  ///
  /// In en, this message translates to:
  /// **'Target Strategy'**
  String get dataSyncTargetStrategy;

  /// No description provided for @dataSyncStrategyTruncate.
  ///
  /// In en, this message translates to:
  /// **'Truncate then sync'**
  String get dataSyncStrategyTruncate;

  /// No description provided for @dataSyncStrategyAppend.
  ///
  /// In en, this message translates to:
  /// **'Append (ignore conflicts)'**
  String get dataSyncStrategyAppend;

  /// No description provided for @dataSyncStrategyReplace.
  ///
  /// In en, this message translates to:
  /// **'Replace'**
  String get dataSyncStrategyReplace;

  /// No description provided for @dataSyncStrategyUpsert.
  ///
  /// In en, this message translates to:
  /// **'Upsert'**
  String get dataSyncStrategyUpsert;

  /// No description provided for @dataSyncServerTimeOnlyHint.
  ///
  /// In en, this message translates to:
  /// **'Server background mode batches by time window only. Numeric segmentation is available in local mode.'**
  String get dataSyncServerTimeOnlyHint;

  /// No description provided for @dataSyncReplaceDowngradeWarning.
  ///
  /// In en, this message translates to:
  /// **'Server background mode has no REPLACE INTO — submitting downgrades to \'truncate then sync\': the target table is emptied first, then fully rewritten from the source.'**
  String get dataSyncReplaceDowngradeWarning;

  /// No description provided for @dataSyncCancelling.
  ///
  /// In en, this message translates to:
  /// **'Cancelling — waiting for the current batch to finish…'**
  String get dataSyncCancelling;

  /// No description provided for @dataSyncSegmentIntervalMs.
  ///
  /// In en, this message translates to:
  /// **'Segment Interval (ms)'**
  String get dataSyncSegmentIntervalMs;

  /// No description provided for @dataSyncPageIntervalMs.
  ///
  /// In en, this message translates to:
  /// **'Page Interval (ms)'**
  String get dataSyncPageIntervalMs;

  /// No description provided for @dataSyncPleaseCompleteConfig.
  ///
  /// In en, this message translates to:
  /// **'Please complete all fields'**
  String get dataSyncPleaseCompleteConfig;

  /// No description provided for @dataSyncConnectionNotFound.
  ///
  /// In en, this message translates to:
  /// **'Connection not found'**
  String get dataSyncConnectionNotFound;

  /// No description provided for @dataSyncFailed.
  ///
  /// In en, this message translates to:
  /// **'Sync failed: {error}'**
  String dataSyncFailed(String error);

  /// No description provided for @dataSyncCancelledByUser.
  ///
  /// In en, this message translates to:
  /// **'Cancelled by user'**
  String get dataSyncCancelledByUser;

  /// No description provided for @dataSyncCompleted.
  ///
  /// In en, this message translates to:
  /// **'Sync completed'**
  String get dataSyncCompleted;

  /// No description provided for @dataSyncStatusSuccess.
  ///
  /// In en, this message translates to:
  /// **'Sync Successful'**
  String get dataSyncStatusSuccess;

  /// No description provided for @dataSyncStatusCancelled.
  ///
  /// In en, this message translates to:
  /// **'Sync Cancelled'**
  String get dataSyncStatusCancelled;

  /// No description provided for @dataSyncResultSourceTable.
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get dataSyncResultSourceTable;

  /// No description provided for @dataSyncResultTargetTable.
  ///
  /// In en, this message translates to:
  /// **'Target'**
  String get dataSyncResultTargetTable;

  /// No description provided for @dataSyncResultSyncedRows.
  ///
  /// In en, this message translates to:
  /// **'Synced Rows'**
  String get dataSyncResultSyncedRows;

  /// No description provided for @dataSyncResultFailedRows.
  ///
  /// In en, this message translates to:
  /// **'Failed Rows'**
  String get dataSyncResultFailedRows;

  /// No description provided for @dataSyncResultDuration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get dataSyncResultDuration;

  /// No description provided for @dataSyncPleaseSelect.
  ///
  /// In en, this message translates to:
  /// **'Please select {label}'**
  String dataSyncPleaseSelect(String label);

  /// No description provided for @dataSyncProgressDetectingSchema.
  ///
  /// In en, this message translates to:
  /// **'Detecting table schema...'**
  String get dataSyncProgressDetectingSchema;

  /// No description provided for @dataSyncProgressCountingRows.
  ///
  /// In en, this message translates to:
  /// **'Counting total rows...'**
  String get dataSyncProgressCountingRows;

  /// No description provided for @dataSyncProgressCalculatingSegments.
  ///
  /// In en, this message translates to:
  /// **'Calculating segments...'**
  String get dataSyncProgressCalculatingSegments;

  /// No description provided for @dataSyncProgressEmptyTable.
  ///
  /// In en, this message translates to:
  /// **'Source table is empty, sync completed'**
  String get dataSyncProgressEmptyTable;

  /// No description provided for @dataSyncProgressTruncatingTarget.
  ///
  /// In en, this message translates to:
  /// **'Truncating target table...'**
  String get dataSyncProgressTruncatingTarget;

  /// No description provided for @dataSyncProgressCancelled.
  ///
  /// In en, this message translates to:
  /// **'Sync cancelled'**
  String get dataSyncProgressCancelled;

  /// No description provided for @dataSyncProgressSyncingSegment.
  ///
  /// In en, this message translates to:
  /// **'Syncing segment {current}/{total}...'**
  String dataSyncProgressSyncingSegment(int current, int total);

  /// No description provided for @dataSyncProgressPageStatus.
  ///
  /// In en, this message translates to:
  /// **'Segment {current}/{total}, synced {synced} / {totalRows} rows'**
  String dataSyncProgressPageStatus(
    int current,
    int total,
    int synced,
    int totalRows,
  );

  /// No description provided for @dataSyncProgressCompleted.
  ///
  /// In en, this message translates to:
  /// **'Sync completed! Success: {synced} rows, Failed: {failed} rows, Skipped: {skipped} rows'**
  String dataSyncProgressCompleted(int synced, int failed, int skipped);

  /// No description provided for @dataSyncErrorDateTimeParse.
  ///
  /// In en, this message translates to:
  /// **'Field `{field}` cannot be parsed as datetime: min={min}, max={max}'**
  String dataSyncErrorDateTimeParse(String field, String min, String max);

  /// No description provided for @dataSyncErrorNumericParse.
  ///
  /// In en, this message translates to:
  /// **'Field `{field}` cannot be parsed as number: min={min}, max={max}'**
  String dataSyncErrorNumericParse(String field, String min, String max);

  /// No description provided for @statsToggle.
  ///
  /// In en, this message translates to:
  /// **'Stats'**
  String get statsToggle;

  /// No description provided for @statsChooseColumns.
  ///
  /// In en, this message translates to:
  /// **'Choose columns'**
  String get statsChooseColumns;

  /// No description provided for @statsApproximateTooltip.
  ///
  /// In en, this message translates to:
  /// **'Values prefixed with ~ are approximate'**
  String get statsApproximateTooltip;

  /// No description provided for @statsApproximateValue.
  ///
  /// In en, this message translates to:
  /// **'Approximate (~{value})'**
  String statsApproximateValue(String value);

  /// No description provided for @statsExactValue.
  ///
  /// In en, this message translates to:
  /// **'Exact'**
  String get statsExactValue;

  /// No description provided for @statsForeignKeys.
  ///
  /// In en, this message translates to:
  /// **'Foreign Keys'**
  String get statsForeignKeys;

  /// No description provided for @statsNoForeignKeys.
  ///
  /// In en, this message translates to:
  /// **'No foreign keys'**
  String get statsNoForeignKeys;

  /// No description provided for @dataSyncProgressSynced.
  ///
  /// In en, this message translates to:
  /// **'Synced {count} rows'**
  String dataSyncProgressSynced(int count);

  /// No description provided for @dataSyncProgressTotal.
  ///
  /// In en, this message translates to:
  /// **'{count} rows'**
  String dataSyncProgressTotal(int count);

  /// No description provided for @dataSyncProgressFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed {count} rows'**
  String dataSyncProgressFailed(int count);

  /// No description provided for @unsavedChangesTitle.
  ///
  /// In en, this message translates to:
  /// **'Unsaved Changes'**
  String get unsavedChangesTitle;

  /// No description provided for @unsavedChangesMessage.
  ///
  /// In en, this message translates to:
  /// **'This tab has unsaved changes. Close without saving?'**
  String get unsavedChangesMessage;

  /// No description provided for @discardChanges.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get discardChanges;

  /// No description provided for @tabCloseConfirmMessage.
  ///
  /// In en, this message translates to:
  /// **'Do you want to save the changes made to \"{title}\" before closing?'**
  String tabCloseConfirmMessage(String title);

  /// No description provided for @bulkCloseDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Unsaved Changes'**
  String get bulkCloseDialogTitle;

  /// No description provided for @bulkCloseDialogMessage.
  ///
  /// In en, this message translates to:
  /// **'The following tabs have unsaved changes:'**
  String get bulkCloseDialogMessage;

  /// No description provided for @bulkCloseSaveAll.
  ///
  /// In en, this message translates to:
  /// **'Save All'**
  String get bulkCloseSaveAll;

  /// No description provided for @bulkCloseDiscardAll.
  ///
  /// In en, this message translates to:
  /// **'Discard All'**
  String get bulkCloseDiscardAll;

  /// No description provided for @bulkCloseReviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Review Tabs'**
  String get bulkCloseReviewTitle;

  /// No description provided for @bulkCloseDecisionSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get bulkCloseDecisionSave;

  /// No description provided for @bulkCloseDecisionDiscard.
  ///
  /// In en, this message translates to:
  /// **'Discard'**
  String get bulkCloseDecisionDiscard;

  /// No description provided for @bulkCloseDecisionPending.
  ///
  /// In en, this message translates to:
  /// **'Keep Open'**
  String get bulkCloseDecisionPending;

  /// No description provided for @bulkCloseSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to save {title}.'**
  String bulkCloseSaveFailed(Object title);

  /// No description provided for @aiPanelOverlayClickMask.
  ///
  /// In en, this message translates to:
  /// **'Click mask'**
  String get aiPanelOverlayClickMask;

  /// No description provided for @aiPanelOverlayCloseOverlay.
  ///
  /// In en, this message translates to:
  /// **'Close overlay'**
  String get aiPanelOverlayCloseOverlay;

  /// No description provided for @aiPanelOverlayDragEdges.
  ///
  /// In en, this message translates to:
  /// **'Drag edges / corners'**
  String get aiPanelOverlayDragEdges;

  /// No description provided for @aiPanelOverlayDragToolbar.
  ///
  /// In en, this message translates to:
  /// **'Drag toolbar'**
  String get aiPanelOverlayDragToolbar;

  /// No description provided for @aiPanelOverlayMoveOverlay.
  ///
  /// In en, this message translates to:
  /// **'Move overlay'**
  String get aiPanelOverlayMoveOverlay;

  /// No description provided for @aiPanelOverlayResizeOverlay.
  ///
  /// In en, this message translates to:
  /// **'Resize overlay'**
  String get aiPanelOverlayResizeOverlay;

  /// No description provided for @aiPanelOverlaySwitchToSidebar.
  ///
  /// In en, this message translates to:
  /// **'Switch to sidebar mode'**
  String get aiPanelOverlaySwitchToSidebar;

  /// No description provided for @aiPanelOverlayToggleMode.
  ///
  /// In en, this message translates to:
  /// **'Toggle overlay/sidebar mode'**
  String get aiPanelOverlayToggleMode;

  /// No description provided for @aiPanelOverlay_aiPanelShortcuts.
  ///
  /// In en, this message translates to:
  /// **'AI panel shortcuts'**
  String get aiPanelOverlay_aiPanelShortcuts;

  /// No description provided for @aiSettingsDisclosureTitle.
  ///
  /// In en, this message translates to:
  /// **'About AI Features'**
  String get aiSettingsDisclosureTitle;

  /// No description provided for @aiSettingsDisclosureBody.
  ///
  /// In en, this message translates to:
  /// **'AI features require your own API Key. All AI requests are sent directly from your device to the AI service provider you choose. DbMaster does not collect your data or relay requests through our servers.'**
  String get aiSettingsDisclosureBody;

  /// Title for export connections dialog
  ///
  /// In en, this message translates to:
  /// **'Export All Connections'**
  String get exportConnectionsTitle;

  /// Title for import connections dialog
  ///
  /// In en, this message translates to:
  /// **'Import Connections'**
  String get importConnectionsTitle;

  /// Label showing number of connections to export
  ///
  /// In en, this message translates to:
  /// **'Connections to export'**
  String get exportConnectionsCount;

  /// Hint for export password field
  ///
  /// In en, this message translates to:
  /// **'Backup password'**
  String get exportPasswordHint;

  /// Hint for confirm export password field
  ///
  /// In en, this message translates to:
  /// **'Confirm backup password'**
  String get confirmExportPasswordHint;

  /// Error shown when export password confirmation does not match
  ///
  /// In en, this message translates to:
  /// **'Passwords do not match'**
  String get passwordsDoNotMatch;

  /// Hint for import password field
  ///
  /// In en, this message translates to:
  /// **'Backup password'**
  String get importPasswordHint;

  /// Button to select export file location
  ///
  /// In en, this message translates to:
  /// **'Save to file'**
  String get selectExportFile;

  /// Button to select import file
  ///
  /// In en, this message translates to:
  /// **'Select backup file'**
  String get selectImportFile;

  /// Error shown when import file picker fails
  ///
  /// In en, this message translates to:
  /// **'Failed to pick file: {error}'**
  String selectImportFileFailed(String error);

  /// Label for conflict strategy dropdown
  ///
  /// In en, this message translates to:
  /// **'If connection name already exists'**
  String get conflictStrategyLabel;

  /// Skip duplicate connections
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get conflictStrategySkip;

  /// Rename imported duplicate connections
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get conflictStrategyRename;

  /// Overwrite existing duplicate connections
  ///
  /// In en, this message translates to:
  /// **'Overwrite'**
  String get conflictStrategyOverwrite;

  /// Snackbar message after successful export
  ///
  /// In en, this message translates to:
  /// **'Connections exported successfully'**
  String get exportSuccess;

  /// Snackbar message after successful import
  ///
  /// In en, this message translates to:
  /// **'Connections imported successfully'**
  String get importSuccess;

  /// Error when import password is wrong
  ///
  /// In en, this message translates to:
  /// **'Invalid password'**
  String get invalidPassword;

  /// Error when import file is invalid
  ///
  /// In en, this message translates to:
  /// **'Invalid or corrupted backup file'**
  String get invalidFile;

  /// Message when no connections are available to export
  ///
  /// In en, this message translates to:
  /// **'No connections to export'**
  String get noConnectionsToExport;

  /// Context menu item to export single connection
  ///
  /// In en, this message translates to:
  /// **'Export This Connection'**
  String get exportThisConnection;

  /// Command palette category for tools
  ///
  /// In en, this message translates to:
  /// **'Tools'**
  String get commandCategoryTools;

  /// Dialog title when password is required to connect
  ///
  /// In en, this message translates to:
  /// **'Password Required'**
  String get passwordRequiredTitle;

  /// Dialog message when password is required, {serverName} is the connection name
  ///
  /// In en, this message translates to:
  /// **'Enter the password for {serverName} to connect'**
  String passwordRequiredMessage(String serverName);

  /// Button in the password prompt to connect to servers that require no authentication
  ///
  /// In en, this message translates to:
  /// **'Connect Without Password'**
  String get connectionConnectNoPassword;

  /// Hint shown on menu entries that are unavailable in embedded local mode
  ///
  /// In en, this message translates to:
  /// **'Remote server only'**
  String get embeddedRequiresRemoteServer;

  /// Title of the dialog shown when an API call returns 401
  ///
  /// In en, this message translates to:
  /// **'Session Expired'**
  String get serverSessionExpiredTitle;

  /// Message of the session-expired dialog
  ///
  /// In en, this message translates to:
  /// **'Your server session has expired or was revoked. Please sign in again to continue.'**
  String get serverSessionExpiredMessage;

  /// Button in the session-expired dialog that opens the connect dialog
  ///
  /// In en, this message translates to:
  /// **'Sign in again'**
  String get serverSessionRelogin;

  /// Button in the connect dialog that retries the stored refresh token without a password
  ///
  /// In en, this message translates to:
  /// **'Reconnect to last server'**
  String get serverReconnectLastSession;

  /// Error shown when one-click reconnect with the stored session failed
  ///
  /// In en, this message translates to:
  /// **'The stored session is no longer valid. Please sign in again.'**
  String get serverReconnectFailed;

  /// Error when emptying table data fails
  ///
  /// In en, this message translates to:
  /// **'Failed to empty table: {error}'**
  String sidebarEmptyTableFailed(String error);

  /// Error when dropping a view fails
  ///
  /// In en, this message translates to:
  /// **'Failed to drop view: {error}'**
  String sidebarDropViewFailed(String error);

  /// Error when dropping a trigger fails
  ///
  /// In en, this message translates to:
  /// **'Failed to drop trigger: {error}'**
  String sidebarDropTriggerFailed(String error);

  /// Error when toggling SQLite WAL mode fails
  ///
  /// In en, this message translates to:
  /// **'Failed to toggle WAL mode: {error}'**
  String sidebarToggleWalFailed(String error);

  /// Error when optimizing SQLite database fails
  ///
  /// In en, this message translates to:
  /// **'Failed to optimize database: {error}'**
  String sidebarOptimizeDbFailed(String error);

  /// Success message when SQLite database is saved to a new file
  ///
  /// In en, this message translates to:
  /// **'Database saved to {path}'**
  String sidebarSaveAsSuccess(String path);

  /// Error when SQLite Save As fails
  ///
  /// In en, this message translates to:
  /// **'Failed to save database: {error}'**
  String sidebarSaveAsFailed(String error);

  /// Warning when the Save As destination file already exists
  ///
  /// In en, this message translates to:
  /// **'File already exists: {path}'**
  String sidebarSaveAsExists(String path);

  /// Error when rebuilding index fails
  ///
  /// In en, this message translates to:
  /// **'Failed to rebuild index: {error}'**
  String sidebarRebuildIndexFailed(String error);

  /// Dialog title for creating a new index
  ///
  /// In en, this message translates to:
  /// **'New Index'**
  String get sidebarNewIndex;

  /// Dialog title for inserting a document into MongoDB collection
  ///
  /// In en, this message translates to:
  /// **'Insert Document'**
  String get sidebarInsertDocument;

  /// Success message when a MongoDB collection is dropped
  ///
  /// In en, this message translates to:
  /// **'Collection {name} dropped'**
  String sidebarCollectionDropped(String name);

  /// Confirmation dialog for dropping a MongoDB collection
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to drop collection \"{name}\"?\n\nThis action cannot be undone.'**
  String sidebarDropCollectionConfirm(String name);

  /// Confirmation dialog for dropping a MongoDB index
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to drop index \"{indexName}\" from \"{collectionName}\"?\n\nThis action cannot be undone.'**
  String sidebarDropIndexConfirm(String indexName, String collectionName);

  /// Confirmation dialog for dropping a table
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to drop table \"{tableName}\"?\n\nThis action cannot be undone.'**
  String sidebarDropTableConfirm(String tableName);

  /// Confirmation dialog for dropping a view
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to drop view \"{viewName}\"?\n\nThis action cannot be undone.'**
  String sidebarDropViewConfirm(String viewName);

  /// Confirmation dialog for emptying table data
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to empty all data from table \"{tableName}\"?\n\nThis action cannot be undone.'**
  String sidebarEmptyTableConfirm(String tableName);

  /// Menu item for creating a new index
  ///
  /// In en, this message translates to:
  /// **'Create New Index'**
  String get sidebarCreateNewIndex;

  /// Menu item for creating a new view
  ///
  /// In en, this message translates to:
  /// **'Create New View'**
  String get sidebarCreateNewView;

  /// Menu item for creating a new materialized view
  ///
  /// In en, this message translates to:
  /// **'Create New Materialized View'**
  String get sidebarCreateNewMaterializedView;

  /// Menu item for creating a new trigger
  ///
  /// In en, this message translates to:
  /// **'Create New Trigger'**
  String get sidebarCreateNewTrigger;

  /// Error when adding column fails
  ///
  /// In en, this message translates to:
  /// **'Failed to add column: {error}'**
  String addColumnFailed(String error);

  /// Error when creating index fails
  ///
  /// In en, this message translates to:
  /// **'Failed to create index: {error}'**
  String createIndexFailed(String error);

  /// Error when dropping table fails
  ///
  /// In en, this message translates to:
  /// **'Failed to drop table: {error}'**
  String dropTableFailed(String error);

  /// Error when inserting document into MongoDB collection fails
  ///
  /// In en, this message translates to:
  /// **'Failed to insert document'**
  String get insertDocumentFailed;

  /// Menu item to empty table data
  ///
  /// In en, this message translates to:
  /// **'Empty Table'**
  String get sidebarEmptyTable;

  /// Snackbar after emptying table
  ///
  /// In en, this message translates to:
  /// **'Table \"{tableName}\" emptied successfully'**
  String sidebarEmptyTableSuccess(String tableName);

  /// Snackbar after dropping an object
  ///
  /// In en, this message translates to:
  /// **'Dropped successfully'**
  String get sidebarDropSuccess;

  /// Dialog title for creating index
  ///
  /// In en, this message translates to:
  /// **'Create Index on \"{tableName}\"'**
  String sidebarCreateIndexTitle(String tableName);

  /// Snackbar after index creation
  ///
  /// In en, this message translates to:
  /// **'Index \"{indexName}\" created on \"{tableName}\"'**
  String sidebarIndexCreated(String indexName, String tableName);

  /// Snackbar after index drop
  ///
  /// In en, this message translates to:
  /// **'Index \"{indexName}\" dropped successfully'**
  String sidebarIndexDropped(String indexName);

  /// Snackbar after index rebuild
  ///
  /// In en, this message translates to:
  /// **'Index \"{indexName}\" rebuilt successfully'**
  String sidebarIndexRebuilt(String indexName);

  /// Menu item to drop a column
  ///
  /// In en, this message translates to:
  /// **'Drop Column'**
  String get sidebarDropColumnTitle;

  /// Menu item to view table structure
  ///
  /// In en, this message translates to:
  /// **'View Structure'**
  String get sidebarViewStructure;

  /// Menu item to browse table data
  ///
  /// In en, this message translates to:
  /// **'Browse Data'**
  String get sidebarBrowseData;

  /// Menu/sidebar refresh button
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get sidebarRefresh;

  /// Menu item to import SQL
  ///
  /// In en, this message translates to:
  /// **'Import SQL'**
  String get sidebarImportSQL;

  /// Dialog title for creating a new table
  ///
  /// In en, this message translates to:
  /// **'New Table'**
  String get sidebarNewTable;

  /// Label for index name input field
  ///
  /// In en, this message translates to:
  /// **'Index Name'**
  String get sidebarIndexName;

  /// Create button label
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get sidebarCreate;

  /// Drop button label
  ///
  /// In en, this message translates to:
  /// **'Drop'**
  String get sidebarDrop;

  /// Validation error when index fields are missing
  ///
  /// In en, this message translates to:
  /// **'Index name and fields are required'**
  String get sidebarIndexFieldsRequired;

  /// Menu item to view collection statistics
  ///
  /// In en, this message translates to:
  /// **'View Stats'**
  String get sidebarViewStats;

  /// Dialog title for dropping a MongoDB collection
  ///
  /// In en, this message translates to:
  /// **'Drop Collection'**
  String get sidebarDropCollectionTitle;

  /// Dialog title for creating a new Redis key
  ///
  /// In en, this message translates to:
  /// **'New Key'**
  String get sidebarNewKey;

  /// Menu item to flush a Redis database
  ///
  /// In en, this message translates to:
  /// **'Flush DB'**
  String get sidebarFlushDB;

  /// Confirmation dialog for flushing Redis database
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to flush {dbName}? This will delete ALL keys in this database.'**
  String sidebarFlushConfirm(String dbName);

  /// Error when flushing Redis database fails
  ///
  /// In en, this message translates to:
  /// **'Failed: {error}'**
  String sidebarFlushFailed(String error);

  /// Snackbar after Redis key creation
  ///
  /// In en, this message translates to:
  /// **'Key \"{key}\" created successfully'**
  String sidebarKeyCreated(String key);

  /// Error when creating Redis key fails
  ///
  /// In en, this message translates to:
  /// **'Failed to create key: {error}'**
  String sidebarKeyFailed(String error);

  /// Error when dropping collection fails
  ///
  /// In en, this message translates to:
  /// **'Failed to drop collection'**
  String get sidebarDropCollectionFailed;

  /// Error when loading database info fails
  ///
  /// In en, this message translates to:
  /// **'Failed to load database info'**
  String get sidebarLoadDbInfoFailed;

  /// Snackbar after table rename
  ///
  /// In en, this message translates to:
  /// **'Table \"{tableName}\" renamed to \"{newName}\"'**
  String renameSuccess(String tableName, String newName);

  /// Dialog title for dropping an index
  ///
  /// In en, this message translates to:
  /// **'Drop Index?'**
  String get dropIndexTitle;

  /// Label for index size in collection statistics
  ///
  /// In en, this message translates to:
  /// **'Index Size'**
  String get sidebarIndexSize;

  /// Database schema field label
  ///
  /// In en, this message translates to:
  /// **'Schema'**
  String get connectionSchema;

  /// SQLite database file field label
  ///
  /// In en, this message translates to:
  /// **'Database File'**
  String get connectionDbFile;

  /// File picker title for SQLite database
  ///
  /// In en, this message translates to:
  /// **'Select SQLite Database File'**
  String get connectionSelectDbFile;

  /// Validation error for missing SQLite file
  ///
  /// In en, this message translates to:
  /// **'Please select a database file'**
  String get connectionDbFileRequired;

  /// SSH private key field label
  ///
  /// In en, this message translates to:
  /// **'Private Key'**
  String get connectionPrivateKey;

  /// File picker title for SSH private key
  ///
  /// In en, this message translates to:
  /// **'Select SSH Private Key'**
  String get connectionSelectSshKey;

  /// SSH key passphrase field label
  ///
  /// In en, this message translates to:
  /// **'Passphrase'**
  String get connectionPassphrase;

  /// SSH key passphrase hint text
  ///
  /// In en, this message translates to:
  /// **'Key Passphrase (optional)'**
  String get connectionKeyPassphrase;

  /// Section header for authentication settings
  ///
  /// In en, this message translates to:
  /// **'Authentication'**
  String get connectionAuthSection;

  /// SSH tunnel section subtitle
  ///
  /// In en, this message translates to:
  /// **'Connect via SSH jump host'**
  String get connectionSshSubtitle;

  /// SSH configuration section header
  ///
  /// In en, this message translates to:
  /// **'SSH Configuration'**
  String get connectionSshConfig;

  /// Default charset option
  ///
  /// In en, this message translates to:
  /// **'Auto (utf8mb4)'**
  String get connectionAutoCharset;

  /// Default system option
  ///
  /// In en, this message translates to:
  /// **'Auto (System)'**
  String get connectionAutoSystem;

  /// Hint text for SSH private key input
  ///
  /// In en, this message translates to:
  /// **'Paste key content or use file picker →'**
  String get connectionPasteKeyHint;

  /// MongoDB cluster connection mode selector label
  ///
  /// In en, this message translates to:
  /// **'Connection Mode'**
  String get connectionMongoMode;

  /// MongoDB direct (single host) connection mode option
  ///
  /// In en, this message translates to:
  /// **'Direct (Single Host)'**
  String get connectionMongoModeDirect;

  /// MongoDB replica set connection mode option
  ///
  /// In en, this message translates to:
  /// **'Replica Set'**
  String get connectionMongoModeReplicaSet;

  /// MongoDB replica set seed host list field label
  ///
  /// In en, this message translates to:
  /// **'Seed Hosts'**
  String get connectionMongoSeedHosts;

  /// Subtitle hint above the MongoDB replica set seed host field
  ///
  /// In en, this message translates to:
  /// **'List all replica-set members (host:port, one per line). The driver auto-discovers the primary; this list is the source of truth.'**
  String get connectionMongoSeedHostsHint;

  /// Validation error for empty MongoDB seed host list
  ///
  /// In en, this message translates to:
  /// **'At least one seed host (host:port) is required'**
  String get connectionMongoSeedHostsRequired;

  /// MongoDB replica set name field label
  ///
  /// In en, this message translates to:
  /// **'Replica Set Name'**
  String get connectionMongoReplicaSetName;

  /// Validation error for empty MongoDB replica set name
  ///
  /// In en, this message translates to:
  /// **'Replica set name is required'**
  String get connectionMongoReplicaSetNameRequired;

  /// MongoDB advanced (paste full connection string) mode option
  ///
  /// In en, this message translates to:
  /// **'Advanced (Connection String)'**
  String get connectionMongoModeAdvanced;

  /// MongoDB sharded cluster (via mongos) connection mode option
  ///
  /// In en, this message translates to:
  /// **'Sharded (mongos)'**
  String get connectionMongoModeSharded;

  /// MongoDB sharded mode mongos router host list field label
  ///
  /// In en, this message translates to:
  /// **'mongos Routers'**
  String get connectionMongoMongosHosts;

  /// Subtitle hint above the MongoDB mongos router host list field
  ///
  /// In en, this message translates to:
  /// **'List all mongos router nodes (host:port, one per line). The driver connects through mongos; sharding is transparent.'**
  String get connectionMongoMongosHostsHint;

  /// Validation error for empty MongoDB mongos router host list
  ///
  /// In en, this message translates to:
  /// **'At least one mongos router (host:port) is required'**
  String get connectionMongoMongosHostsRequired;

  /// Validation error for a malformed host:port entry in a MongoDB host list
  ///
  /// In en, this message translates to:
  /// **'Invalid entry (expected host or host:port)'**
  String get connectionMongoInvalidHostPort;

  /// MongoDB advanced mode paste-box field label
  ///
  /// In en, this message translates to:
  /// **'Connection String'**
  String get connectionMongoConnectionString;

  /// Subtitle hint above the MongoDB advanced connection string field
  ///
  /// In en, this message translates to:
  /// **'Paste a full connection string (mongodb:// or mongodb+srv://, incl. Atlas). Credentials are stripped automatically; the password is stored encrypted separately.'**
  String get connectionMongoConnectionStringHint;

  /// Validation error for empty MongoDB connection string
  ///
  /// In en, this message translates to:
  /// **'Please paste a connection string'**
  String get connectionMongoConnectionStringRequired;

  /// Validation error for an unparseable MongoDB connection string
  ///
  /// In en, this message translates to:
  /// **'Invalid connection string (must start with mongodb:// or mongodb+srv://)'**
  String get connectionMongoConnectionStringInvalid;

  /// Validation error for invalid port number
  ///
  /// In en, this message translates to:
  /// **'Invalid port'**
  String get connInvalidPort;

  /// Validation error for missing username
  ///
  /// In en, this message translates to:
  /// **'Username is required'**
  String get connUsernameRequired;

  /// Validation error for missing connection name
  ///
  /// In en, this message translates to:
  /// **'Connection name is required'**
  String get connNameRequired;

  /// Validation error for missing host
  ///
  /// In en, this message translates to:
  /// **'Host is required'**
  String get connHostRequired;

  /// Validation error for missing port
  ///
  /// In en, this message translates to:
  /// **'Port is required'**
  String get connPortRequired;

  /// Validation error for required field
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get connRequired;

  /// Code snippet category filter - show all
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get snippetCategoryAll;

  /// Code snippet category - DML (Data Manipulation Language)
  ///
  /// In en, this message translates to:
  /// **'DML'**
  String get snippetCategoryDML;

  /// Code snippet category - DDL (Data Definition Language)
  ///
  /// In en, this message translates to:
  /// **'DDL'**
  String get snippetCategoryDDL;

  /// Code snippet category - Query
  ///
  /// In en, this message translates to:
  /// **'Query'**
  String get snippetCategoryQuery;

  /// Code snippet category - Utility
  ///
  /// In en, this message translates to:
  /// **'Utility'**
  String get snippetCategoryUtility;

  /// Code snippet category - Custom
  ///
  /// In en, this message translates to:
  /// **'Custom'**
  String get snippetCategoryCustom;

  /// Tooltip for manage groups button
  ///
  /// In en, this message translates to:
  /// **'Manage Groups'**
  String get sidebarManageGroups;

  /// Tooltip for new group button
  ///
  /// In en, this message translates to:
  /// **'New Group'**
  String get sidebarNewGroup;

  /// Label for group name input
  ///
  /// In en, this message translates to:
  /// **'Group Name'**
  String get sidebarGroupName;

  /// Hint text for group name input
  ///
  /// In en, this message translates to:
  /// **'e.g., Production'**
  String get sidebarGroupHint;

  /// Hint text for sidebar filter
  ///
  /// In en, this message translates to:
  /// **'Filter...'**
  String get sidebarFilterHint;

  /// Snackbar after table export
  ///
  /// In en, this message translates to:
  /// **'Table \"{tableName}\" exported to clipboard'**
  String sidebarTableExported(String tableName);

  /// Error when export fails
  ///
  /// In en, this message translates to:
  /// **'Export failed: {error}'**
  String sidebarExportFailed(String error);

  /// Error when connection fails
  ///
  /// In en, this message translates to:
  /// **'Failed to connect to {serverName}'**
  String sidebarConnectFailed(String serverName);

  /// Snackbar after super table deletion
  ///
  /// In en, this message translates to:
  /// **'SuperTable \"{name}\" deleted'**
  String sidebarSuperTableDeleted(String name);

  /// Error when delete fails
  ///
  /// In en, this message translates to:
  /// **'Failed to delete: {error}'**
  String sidebarDeleteFailed(String error);

  /// Snackbar after adding column
  ///
  /// In en, this message translates to:
  /// **'Column \"{column}\" added to \"{table}\"'**
  String sidebarColumnAdded(String column, String table);

  /// Label for column name input
  ///
  /// In en, this message translates to:
  /// **'Column Name'**
  String get sidebarColumnName;

  /// Label for data type input
  ///
  /// In en, this message translates to:
  /// **'Data Type'**
  String get sidebarDataType;

  /// Hint text for data type input
  ///
  /// In en, this message translates to:
  /// **'TEXT, INTEGER, REAL, BLOB, etc.'**
  String get sidebarDataTypeHint;

  /// Label for optional default value input
  ///
  /// In en, this message translates to:
  /// **'Default Value (optional)'**
  String get sidebarDefaultValueOptional;

  /// Label for Redis key type
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get sidebarRedisType;

  /// Label for Redis hash field
  ///
  /// In en, this message translates to:
  /// **'Field'**
  String get sidebarRedisField;

  /// Label for Redis hash field value
  ///
  /// In en, this message translates to:
  /// **'Field Value'**
  String get sidebarRedisFieldValue;

  /// Label for Redis value input
  ///
  /// In en, this message translates to:
  /// **'Value'**
  String get sidebarRedisValue;

  /// Label for Redis TTL input
  ///
  /// In en, this message translates to:
  /// **'Expire After'**
  String get sidebarRedisExpire;

  /// Validation error when Redis key fields are missing
  ///
  /// In en, this message translates to:
  /// **'Please fill in all required fields'**
  String get sidebarRedisFieldsRequired;

  /// Tooltip for command palette button
  ///
  /// In en, this message translates to:
  /// **'Command Palette'**
  String get sidebarCommandPalette;

  /// Tooltip for case sensitive toggle
  ///
  /// In en, this message translates to:
  /// **'Case Sensitive'**
  String get sidebarCaseSensitive;

  /// Tooltip for collapse button
  ///
  /// In en, this message translates to:
  /// **'Collapse'**
  String get sidebarCollapse;

  /// Label for index columns input
  ///
  /// In en, this message translates to:
  /// **'Columns'**
  String get sidebarIndexColumns;

  /// Hint text for index columns input
  ///
  /// In en, this message translates to:
  /// **'column1, column2, ...'**
  String get sidebarIndexColumnsHint;

  /// Hint text for MongoDB index fields
  ///
  /// In en, this message translates to:
  /// **'e.g. name, email, age'**
  String get sidebarIndexFieldsHint;

  /// Hint text for column name input
  ///
  /// In en, this message translates to:
  /// **'column_name'**
  String get sidebarColumnNameHint;

  /// Hint text for tag name input
  ///
  /// In en, this message translates to:
  /// **'tag_name'**
  String get sidebarTagNameHint;

  /// Hint text for MongoDB document insert
  ///
  /// In en, this message translates to:
  /// **'field: value'**
  String get sidebarInsertDocHint;

  /// Hint text for JSON cell editor
  ///
  /// In en, this message translates to:
  /// **'JSON...'**
  String get sidebarJsonHint;

  /// Label for super table name input
  ///
  /// In en, this message translates to:
  /// **'SuperTable Name'**
  String get sidebarSuperTableName;

  /// Label for optional comment input
  ///
  /// In en, this message translates to:
  /// **'Comment (Optional)'**
  String get sidebarCommentOptional;

  /// Tooltip for new chat button
  ///
  /// In en, this message translates to:
  /// **'New Chat'**
  String get connectionNewChat;

  /// Short error for failed connection test
  ///
  /// In en, this message translates to:
  /// **'Test failed: {error}'**
  String connectionTestFailedShort(String error);

  /// Error when MongoDB document insert fails
  ///
  /// In en, this message translates to:
  /// **'Invalid JSON or insert failed: {error}'**
  String sidebarFailedInsert(String error);

  /// Snackbar after collection drop
  ///
  /// In en, this message translates to:
  /// **'Collection {name} dropped'**
  String sidebarCollectionDroppedSnack(String name);

  /// Error when creating file fails
  ///
  /// In en, this message translates to:
  /// **'Failed to create file: {error}'**
  String sidebarFileCreateFailed(String error);

  /// Error when saving fails
  ///
  /// In en, this message translates to:
  /// **'Failed to save: {error}'**
  String sidebarSaveFailed(String error);

  /// Snackbar after copying SQL
  ///
  /// In en, this message translates to:
  /// **'SQL copied to clipboard'**
  String get sidebarSqlCopied;

  /// Snackbar after exporting logs
  ///
  /// In en, this message translates to:
  /// **'Logs exported to clipboard as CSV'**
  String get sidebarLogsExported;

  /// Tooltip for begin transaction button
  ///
  /// In en, this message translates to:
  /// **'BEGIN TRANSACTION'**
  String get toolbarBeginTransaction;

  /// Tooltip for commit button
  ///
  /// In en, this message translates to:
  /// **'COMMIT'**
  String get toolbarCommit;

  /// Tooltip for rollback button
  ///
  /// In en, this message translates to:
  /// **'ROLLBACK'**
  String get toolbarRollback;

  /// Tooltip for query plan button
  ///
  /// In en, this message translates to:
  /// **'Query Plan'**
  String get toolbarQueryPlan;

  /// Tooltip for PII masking settings button
  ///
  /// In en, this message translates to:
  /// **'PII Masking Settings'**
  String get toolbarPiiMasking;

  /// Tooltip for close all results button
  ///
  /// In en, this message translates to:
  /// **'Close all results'**
  String get toolbarCloseAll;

  /// Hint text for search field in dialogs
  ///
  /// In en, this message translates to:
  /// **'Search SQL or connection...'**
  String get dlgSearchHint;

  /// Tooltip for open in new tab button
  ///
  /// In en, this message translates to:
  /// **'Open in new tab'**
  String get dlgOpenInNewTab;

  /// Tooltip for copy SQL button
  ///
  /// In en, this message translates to:
  /// **'Copy SQL'**
  String get dlgCopySQL;

  /// Hint text for database selection
  ///
  /// In en, this message translates to:
  /// **'Select database'**
  String get dlgChooseDatabase;

  /// Hint text for table selection in import
  ///
  /// In en, this message translates to:
  /// **'Select existing table or leave blank for AI inference'**
  String get dlgChooseTableOrAI;

  /// Tooltip for remove file button
  ///
  /// In en, this message translates to:
  /// **'Remove file'**
  String get dlgRemoveFile;

  /// Hint text for skipping import
  ///
  /// In en, this message translates to:
  /// **'Skip import'**
  String get dlgSkipImport;

  /// Tooltip for delete parameter button
  ///
  /// In en, this message translates to:
  /// **'Delete parameter'**
  String get dlgDeleteParam;

  /// Label for database name input
  ///
  /// In en, this message translates to:
  /// **'Database Name'**
  String get dbDialogDbName;

  /// Hint text for database name input
  ///
  /// In en, this message translates to:
  /// **'Enter database name'**
  String get dbDialogDbNameHint;

  /// Label for optional charset input
  ///
  /// In en, this message translates to:
  /// **'Character Set (optional)'**
  String get dbDialogCharsetOptional;

  /// Label for optional collation input
  ///
  /// In en, this message translates to:
  /// **'Collation (optional)'**
  String get dbDialogCollationOptional;

  /// Label for index name input
  ///
  /// In en, this message translates to:
  /// **'Index Name'**
  String get dbDialogIndexName;

  /// Label for schema input
  ///
  /// In en, this message translates to:
  /// **'Schema'**
  String get dbDialogSchema;

  /// Label for tablespace input
  ///
  /// In en, this message translates to:
  /// **'Tablespace'**
  String get dbDialogTablespace;

  /// Checkbox label for enabling filter
  ///
  /// In en, this message translates to:
  /// **'Enable'**
  String get filterEnable;

  /// Label for range filter start value
  ///
  /// In en, this message translates to:
  /// **'From'**
  String get filterFrom;

  /// Label for range filter end value
  ///
  /// In en, this message translates to:
  /// **'To'**
  String get filterTo;

  /// Button label for clearing filter
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get filterClear;

  /// Button label for retrying after error
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get errorRetry;

  /// Button label for reporting an issue
  ///
  /// In en, this message translates to:
  /// **'Report Issue'**
  String get errorReport;

  /// Tooltip for opening existing SQLite database
  ///
  /// In en, this message translates to:
  /// **'Open existing database'**
  String get sqliteOpenExisting;

  /// Tooltip for creating new SQLite database
  ///
  /// In en, this message translates to:
  /// **'Create new database'**
  String get sqliteCreateNew;

  /// No description provided for @focusModeEnabled.
  ///
  /// In en, this message translates to:
  /// **'Focus Mode'**
  String get focusModeEnabled;

  /// No description provided for @focusModeDisabled.
  ///
  /// In en, this message translates to:
  /// **'Exit Focus Mode'**
  String get focusModeDisabled;

  /// Search scope option: all
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get sidebarSearchScopeAll;

  /// Search scope option: connection
  ///
  /// In en, this message translates to:
  /// **'Connection'**
  String get sidebarSearchScopeConnection;

  /// Search scope option: database
  ///
  /// In en, this message translates to:
  /// **'Database'**
  String get sidebarSearchScopeDatabase;

  /// Search scope option: table
  ///
  /// In en, this message translates to:
  /// **'Table'**
  String get sidebarSearchScopeTable;

  /// Search scope option: view
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get sidebarSearchScopeView;

  /// Search scope option: procedure
  ///
  /// In en, this message translates to:
  /// **'Procedure'**
  String get sidebarSearchScopeProcedure;

  /// Search scope option: trigger
  ///
  /// In en, this message translates to:
  /// **'Trigger'**
  String get sidebarSearchScopeTrigger;

  /// Search scope option: event
  ///
  /// In en, this message translates to:
  /// **'Event'**
  String get sidebarSearchScopeEvent;

  /// Tooltip showing current search scope
  ///
  /// In en, this message translates to:
  /// **'Search scope: {scope}'**
  String sidebarSearchScopeTooltip(String scope);

  /// Menu item to drop an event
  ///
  /// In en, this message translates to:
  /// **'Drop Event'**
  String get sidebarDropEvent;

  /// Confirmation message before dropping an event
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to drop event \"{name}\"?'**
  String sidebarDropEventConfirm(String name);

  /// Error message when an event operation fails
  ///
  /// In en, this message translates to:
  /// **'Event operation failed: {error}'**
  String sidebarEventOperationFailed(String error);

  /// Shown when an event has no definition
  ///
  /// In en, this message translates to:
  /// **'No definition'**
  String get sidebarEventNoDefinition;

  /// Menu item to drop a synonym
  ///
  /// In en, this message translates to:
  /// **'Drop Synonym'**
  String get sidebarDropSynonym;

  /// Confirmation message before dropping a synonym
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to drop synonym \"{name}\"?'**
  String sidebarDropSynonymConfirm(String name);

  /// Error message when a synonym operation fails
  ///
  /// In en, this message translates to:
  /// **'Synonym operation failed: {error}'**
  String sidebarSynonymOperationFailed(String error);

  /// Menu item to enable an event
  ///
  /// In en, this message translates to:
  /// **'Enable'**
  String get sidebarEnableEvent;

  /// Menu item to disable an event
  ///
  /// In en, this message translates to:
  /// **'Disable'**
  String get sidebarDisableEvent;

  /// Menu item to view event properties
  ///
  /// In en, this message translates to:
  /// **'Properties'**
  String get sidebarEventProperties;

  /// Label for database synonyms
  ///
  /// In en, this message translates to:
  /// **'Synonyms'**
  String get sidebarSynonyms;

  /// Menu item to browse a synonym
  ///
  /// In en, this message translates to:
  /// **'Browse'**
  String get sidebarBrowseSynonym;

  /// Menu item to script synonym as SELECT
  ///
  /// In en, this message translates to:
  /// **'Script as SELECT'**
  String get sidebarScriptSynonymAsSelect;

  /// Label showing remaining items
  ///
  /// In en, this message translates to:
  /// **'Show remaining {remaining}'**
  String sidebarShowRemaining(int remaining);

  /// Button to load more items
  ///
  /// In en, this message translates to:
  /// **'Load {batchSize} more ({remaining} remaining)'**
  String sidebarLoadMore(int batchSize, int remaining);

  /// Error when source and target database types differ
  ///
  /// In en, this message translates to:
  /// **'Source and target database types do not match'**
  String get schemaDiffDatabaseTypeMismatch;

  /// Generic error with message
  ///
  /// In en, this message translates to:
  /// **'Error: {message}'**
  String schemaDiffErrorWithMessage(String message);

  /// Button to retry schema diff capture
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get schemaDiffRetryButton;

  /// Title shown while capturing schema
  ///
  /// In en, this message translates to:
  /// **'Capturing Schema'**
  String get schemaDiffCapturingTitle;

  /// Label for source schema/database
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get schemaDiffSourceLabel;

  /// Label for target schema/database
  ///
  /// In en, this message translates to:
  /// **'Target'**
  String get schemaDiffTargetLabel;

  /// Shown while cancelling capture
  ///
  /// In en, this message translates to:
  /// **'Cancelling...'**
  String get schemaDiffCancelling;

  /// Button to cancel capture
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get schemaDiffCancelButton;

  /// Shown while loading diff preview
  ///
  /// In en, this message translates to:
  /// **'Loading preview...'**
  String get schemaDiffResultsPreviewLoading;

  /// Capture phase: starting
  ///
  /// In en, this message translates to:
  /// **'Starting'**
  String get schemaDiffPhaseStarting;

  /// Capture phase: listing tables
  ///
  /// In en, this message translates to:
  /// **'Listing tables'**
  String get schemaDiffPhaseListingTables;

  /// Capture phase: capturing tables
  ///
  /// In en, this message translates to:
  /// **'Capturing tables'**
  String get schemaDiffPhaseCapturingTables;

  /// Capture phase: capturing create statements
  ///
  /// In en, this message translates to:
  /// **'Capturing create statements'**
  String get schemaDiffPhaseCapturingCreateStatements;

  /// Capture phase: capturing views
  ///
  /// In en, this message translates to:
  /// **'Capturing views'**
  String get schemaDiffPhaseCapturingViews;

  /// Capture phase: capturing procedures
  ///
  /// In en, this message translates to:
  /// **'Capturing procedures'**
  String get schemaDiffPhaseCapturingProcedures;

  /// Capture phase: completed
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get schemaDiffPhaseCompleted;

  /// Capture phase: cancelled
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get schemaDiffPhaseCancelled;

  /// Capture phase: error
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get schemaDiffPhaseError;

  /// Capture phase: waiting
  ///
  /// In en, this message translates to:
  /// **'Waiting'**
  String get schemaDiffPhaseWaiting;

  /// Error when schema capture did not complete
  ///
  /// In en, this message translates to:
  /// **'Schema capture incomplete'**
  String get schemaDiffCaptureIncomplete;

  /// Shown after dry run completes
  ///
  /// In en, this message translates to:
  /// **'Dry run completed'**
  String get schemaDiffDryRunCompleted;

  /// Shown after sync succeeds
  ///
  /// In en, this message translates to:
  /// **'Sync completed successfully'**
  String get schemaDiffSyncSuccess;

  /// Shown after sync fails
  ///
  /// In en, this message translates to:
  /// **'Sync failed: {message}'**
  String schemaDiffSyncFailed(String message);

  /// Hint for connection dropdown
  ///
  /// In en, this message translates to:
  /// **'Select connection'**
  String get schemaDiffSelectConnectionHint;

  /// Hint for database dropdown
  ///
  /// In en, this message translates to:
  /// **'Select database'**
  String get schemaDiffSelectDatabaseHint;

  /// Section title for added tables
  ///
  /// In en, this message translates to:
  /// **'Added tables'**
  String get schemaDiffAddedTables;

  /// Section title for removed tables
  ///
  /// In en, this message translates to:
  /// **'Removed tables'**
  String get schemaDiffRemovedTables;

  /// Section title for modified tables
  ///
  /// In en, this message translates to:
  /// **'Modified tables'**
  String get schemaDiffModifiedTables;

  /// Section title for unchanged tables
  ///
  /// In en, this message translates to:
  /// **'Unchanged tables'**
  String get schemaDiffUnchangedTables;

  /// Section title for detailed changes
  ///
  /// In en, this message translates to:
  /// **'Detailed changes'**
  String get schemaDiffDetailedChanges;

  /// Section title for column changes
  ///
  /// In en, this message translates to:
  /// **'Columns'**
  String get schemaDiffColumnChanges;

  /// Section title for index changes
  ///
  /// In en, this message translates to:
  /// **'Indexes'**
  String get schemaDiffIndexChanges;

  /// Section title for view changes
  ///
  /// In en, this message translates to:
  /// **'Views'**
  String get schemaDiffViewChanges;

  /// Section title for procedure changes
  ///
  /// In en, this message translates to:
  /// **'Procedures'**
  String get schemaDiffProcedureChanges;

  /// Shown when there are no detailed changes
  ///
  /// In en, this message translates to:
  /// **'No detailed changes'**
  String get schemaDiffNoDetailedChanges;

  /// Shown when there are no differences
  ///
  /// In en, this message translates to:
  /// **'No differences'**
  String get schemaDiffNoDifferences;

  /// Shown when there are no results
  ///
  /// In en, this message translates to:
  /// **'No results'**
  String get schemaDiffNoResults;

  /// Hint text for diff search
  ///
  /// In en, this message translates to:
  /// **'Search objects...'**
  String get schemaDiffSearchHint;

  /// Filter label for added items
  ///
  /// In en, this message translates to:
  /// **'Added'**
  String get schemaDiffFilterAdded;

  /// Filter label for modified items
  ///
  /// In en, this message translates to:
  /// **'Modified'**
  String get schemaDiffFilterModified;

  /// Filter label for removed items
  ///
  /// In en, this message translates to:
  /// **'Removed'**
  String get schemaDiffFilterRemoved;

  /// Object type filter: tables
  ///
  /// In en, this message translates to:
  /// **'Tables'**
  String get schemaDiffObjectTypeTables;

  /// Object type filter: views
  ///
  /// In en, this message translates to:
  /// **'Views'**
  String get schemaDiffObjectTypeViews;

  /// Object type filter: procedures
  ///
  /// In en, this message translates to:
  /// **'Procedures'**
  String get schemaDiffObjectTypeProcedures;

  /// Status label for added
  ///
  /// In en, this message translates to:
  /// **'Added'**
  String get schemaDiffStatusAdded;

  /// Status label for removed
  ///
  /// In en, this message translates to:
  /// **'Removed'**
  String get schemaDiffStatusRemoved;

  /// Status label for modified
  ///
  /// In en, this message translates to:
  /// **'Modified'**
  String get schemaDiffStatusModified;

  /// Status label for unchanged
  ///
  /// In en, this message translates to:
  /// **'Unchanged'**
  String get schemaDiffStatusUnchanged;

  /// Shows number of changes
  ///
  /// In en, this message translates to:
  /// **'{count} changes'**
  String schemaDiffChangeCount(int count);

  /// Label for columns
  ///
  /// In en, this message translates to:
  /// **'Columns'**
  String get schemaDiffColumns;

  /// Label for indexes
  ///
  /// In en, this message translates to:
  /// **'Indexes'**
  String get schemaDiffIndexes;

  /// Label for DDL comparison section
  ///
  /// In en, this message translates to:
  /// **'DDL comparison'**
  String get schemaDiffDdlComparison;

  /// Label for primary key
  ///
  /// In en, this message translates to:
  /// **'PK'**
  String get schemaDiffColumnPk;

  /// Label for NOT NULL constraint
  ///
  /// In en, this message translates to:
  /// **'NOT NULL'**
  String get schemaDiffColumnNotNull;

  /// Label for unique index
  ///
  /// In en, this message translates to:
  /// **'Unique'**
  String get schemaDiffIndexUnique;

  /// Hint for sync plan generation
  ///
  /// In en, this message translates to:
  /// **'Generate sync plan'**
  String get schemaDiffGenerateSyncPlanHint;

  /// Button to generate sync plan
  ///
  /// In en, this message translates to:
  /// **'Generate Plan'**
  String get schemaDiffGenerateSyncPlanButton;

  /// Shows number of operations
  ///
  /// In en, this message translates to:
  /// **'{count} operations'**
  String schemaDiffOperationsCount(int count);

  /// Label for dry run mode
  ///
  /// In en, this message translates to:
  /// **'Dry run'**
  String get schemaDiffDryRunMode;

  /// Button to perform dry run
  ///
  /// In en, this message translates to:
  /// **'Dry Run'**
  String get schemaDiffDryRunButton;

  /// Button to execute sync plan
  ///
  /// In en, this message translates to:
  /// **'Execute'**
  String get schemaDiffExecuteButton;

  /// Shows number of failed operations
  ///
  /// In en, this message translates to:
  /// **'{count} operations failed'**
  String schemaDiffOperationsFailed(int count);

  /// Title for execute confirmation
  ///
  /// In en, this message translates to:
  /// **'Execute sync plan?'**
  String get schemaDiffExecuteConfirmTitle;

  /// Message for execute confirmation
  ///
  /// In en, this message translates to:
  /// **'This will apply the generated sync plan to the target database. Continue?'**
  String get schemaDiffExecuteConfirmMessage;

  /// Button to cancel execution
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get schemaDiffExecuteConfirmCancel;

  /// Button to confirm execution
  ///
  /// In en, this message translates to:
  /// **'Execute'**
  String get schemaDiffExecuteConfirmExecute;

  /// Context menu item to save a schema snapshot
  ///
  /// In en, this message translates to:
  /// **'Save Schema Snapshot'**
  String get schemaDiffSaveSnapshot;

  /// Title for the snapshot management panel
  ///
  /// In en, this message translates to:
  /// **'Schema Snapshots'**
  String get schemaDiffSnapshotTitle;

  /// Empty state message for snapshot panel
  ///
  /// In en, this message translates to:
  /// **'No snapshots saved yet'**
  String get schemaDiffSnapshotNoSnapshots;

  /// Confirmation message for snapshot deletion
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete this snapshot?'**
  String get schemaDiffSnapshotDeleteConfirm;

  /// Title shown during sync execution
  ///
  /// In en, this message translates to:
  /// **'Executing Sync Plan'**
  String get schemaDiffSyncExecuting;

  /// Title shown after sync execution completes
  ///
  /// In en, this message translates to:
  /// **'Sync Complete'**
  String get schemaDiffSyncComplete;

  /// Message shown when PG transaction is rolled back
  ///
  /// In en, this message translates to:
  /// **'Transaction rolled back due to errors'**
  String get schemaDiffSyncRollback;

  /// No description provided for @viewMenuTitle.
  ///
  /// In en, this message translates to:
  /// **'View'**
  String get viewMenuTitle;

  /// No description provided for @viewMenuToggleSidebar.
  ///
  /// In en, this message translates to:
  /// **'Sidebar'**
  String get viewMenuToggleSidebar;

  /// No description provided for @viewMenuToggleAiPanel.
  ///
  /// In en, this message translates to:
  /// **'AI Panel'**
  String get viewMenuToggleAiPanel;

  /// No description provided for @viewMenuToggleBottomPanel.
  ///
  /// In en, this message translates to:
  /// **'Bottom Panel'**
  String get viewMenuToggleBottomPanel;

  /// No description provided for @viewMenuExpandWorkspace.
  ///
  /// In en, this message translates to:
  /// **'Expand Workspace'**
  String get viewMenuExpandWorkspace;

  /// No description provided for @viewMenuLayoutPresets.
  ///
  /// In en, this message translates to:
  /// **'Layout Presets'**
  String get viewMenuLayoutPresets;

  /// No description provided for @viewMenuLayoutPresetDefault.
  ///
  /// In en, this message translates to:
  /// **'Default'**
  String get viewMenuLayoutPresetDefault;

  /// No description provided for @viewMenuLayoutPresetExpand.
  ///
  /// In en, this message translates to:
  /// **'Expand Workspace'**
  String get viewMenuLayoutPresetExpand;

  /// No description provided for @expandWorkspaceEnabled.
  ///
  /// In en, this message translates to:
  /// **'Expand Workspace'**
  String get expandWorkspaceEnabled;

  /// No description provided for @expandWorkspaceDisabled.
  ///
  /// In en, this message translates to:
  /// **'Exit Expand Workspace'**
  String get expandWorkspaceDisabled;

  /// No description provided for @bottomPanelTabResults.
  ///
  /// In en, this message translates to:
  /// **'Results'**
  String get bottomPanelTabResults;

  /// No description provided for @bottomPanelTabLogs.
  ///
  /// In en, this message translates to:
  /// **'Logs'**
  String get bottomPanelTabLogs;

  /// No description provided for @bottomPanelTabHistory.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get bottomPanelTabHistory;

  /// No description provided for @bottomPanelTabTasks.
  ///
  /// In en, this message translates to:
  /// **'Tasks'**
  String get bottomPanelTabTasks;

  /// No description provided for @bottomPanelResultsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No results to display'**
  String get bottomPanelResultsEmpty;

  /// No description provided for @bottomPanelResultsEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Execute a query to see results'**
  String get bottomPanelResultsEmptyHint;

  /// No description provided for @bottomPanelLogsTitle.
  ///
  /// In en, this message translates to:
  /// **'Query Audit Log'**
  String get bottomPanelLogsTitle;

  /// No description provided for @bottomPanelLogsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No audit logs yet'**
  String get bottomPanelLogsEmpty;

  /// No description provided for @bottomPanelLogsEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Execute queries to start recording logs'**
  String get bottomPanelLogsEmptyHint;

  /// No description provided for @bottomPanelLogsStatusAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get bottomPanelLogsStatusAll;

  /// No description provided for @bottomPanelLogsStatusSuccess.
  ///
  /// In en, this message translates to:
  /// **'Success'**
  String get bottomPanelLogsStatusSuccess;

  /// No description provided for @bottomPanelLogsStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get bottomPanelLogsStatusFailed;

  /// No description provided for @bottomPanelLogsExport.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get bottomPanelLogsExport;

  /// No description provided for @bottomPanelLogsClearAll.
  ///
  /// In en, this message translates to:
  /// **'Clear All'**
  String get bottomPanelLogsClearAll;

  /// No description provided for @bottomPanelLogsConfirmClearTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear Audit Logs'**
  String get bottomPanelLogsConfirmClearTitle;

  /// No description provided for @bottomPanelLogsConfirmClearMessage.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to clear all audit logs? This action cannot be undone.'**
  String get bottomPanelLogsConfirmClearMessage;

  /// No description provided for @bottomPanelHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'SQL History'**
  String get bottomPanelHistoryTitle;

  /// No description provided for @bottomPanelHistoryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No history yet'**
  String get bottomPanelHistoryEmpty;

  /// No description provided for @bottomPanelHistoryFilterAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get bottomPanelHistoryFilterAll;

  /// No description provided for @bottomPanelHistoryJustNow.
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get bottomPanelHistoryJustNow;

  /// No description provided for @bottomPanelHistoryMinutesAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} minutes ago'**
  String bottomPanelHistoryMinutesAgo(int count);

  /// No description provided for @bottomPanelHistoryHoursAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} hours ago'**
  String bottomPanelHistoryHoursAgo(int count);

  /// No description provided for @bottomPanelHistoryDaysAgo.
  ///
  /// In en, this message translates to:
  /// **'{count} days ago'**
  String bottomPanelHistoryDaysAgo(int count);

  /// No description provided for @bottomPanelHistoryDateFormat.
  ///
  /// In en, this message translates to:
  /// **'{month}/{day} {hour}:{minute}'**
  String bottomPanelHistoryDateFormat(
    int month,
    int day,
    int hour,
    String minute,
  );

  /// No description provided for @bottomPanelHistoryDeleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted \"{sql}\"'**
  String bottomPanelHistoryDeleted(String sql);

  /// No description provided for @bottomPanelHistoryDeletedCount.
  ///
  /// In en, this message translates to:
  /// **'Deleted {count} history records'**
  String bottomPanelHistoryDeletedCount(int count);

  /// No description provided for @bottomPanelHistoryCopied.
  ///
  /// In en, this message translates to:
  /// **'SQL copied to clipboard'**
  String get bottomPanelHistoryCopied;

  /// No description provided for @bottomPanelHistoryUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get bottomPanelHistoryUndo;

  /// No description provided for @bottomPanelStatusRows.
  ///
  /// In en, this message translates to:
  /// **'{count} rows'**
  String bottomPanelStatusRows(int count);

  /// No description provided for @bottomPanelStatusClickTabForError.
  ///
  /// In en, this message translates to:
  /// **'Click tab to view error details'**
  String get bottomPanelStatusClickTabForError;

  /// No description provided for @resultsQueryFailedTitle.
  ///
  /// In en, this message translates to:
  /// **'Query failed'**
  String get resultsQueryFailedTitle;

  /// No description provided for @resultsUnknownError.
  ///
  /// In en, this message translates to:
  /// **'Unknown error'**
  String get resultsUnknownError;

  /// Title of the Query History section in the left sidebar
  ///
  /// In en, this message translates to:
  /// **'Query History'**
  String get queryHistoryTitle;

  /// Message shown when no query history exists for the selected connection
  ///
  /// In en, this message translates to:
  /// **'No queries yet — run a query to see it here'**
  String get queryHistoryEmpty;

  /// Message shown while query history is loading
  ///
  /// In en, this message translates to:
  /// **'Loading history...'**
  String get queryHistoryLoading;

  /// Hint text for the query history search box
  ///
  /// In en, this message translates to:
  /// **'Search history...'**
  String get queryHistorySearchHint;

  /// Column header for query execution timestamp in the history table
  ///
  /// In en, this message translates to:
  /// **'Executed At'**
  String get queryHistoryExecutedAt;

  /// Column header for SQL preview in the history table
  ///
  /// In en, this message translates to:
  /// **'SQL Preview'**
  String get queryHistorySqlPreview;

  /// Column header for query execution duration in the history table
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get queryHistoryDuration;

  /// Column header for row count in the history table
  ///
  /// In en, this message translates to:
  /// **'Row Count'**
  String get queryHistoryRowCount;

  /// Status label for a successful query execution
  ///
  /// In en, this message translates to:
  /// **'Success'**
  String get queryHistoryStatusSuccess;

  /// Status label for a failed query execution
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get queryHistoryStatusError;

  /// Menu item to clear all history for the current connection
  ///
  /// In en, this message translates to:
  /// **'Clear all history'**
  String get queryHistoryClearAll;

  /// Context menu item to delete a history entry
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get queryHistoryDelete;

  /// Context menu item to rename a history entry
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get queryHistoryRename;

  /// Confirmation message before clearing all history for the current connection
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to clear all history for this connection?'**
  String get queryHistoryConfirmClearAll;

  /// Confirmation message before deleting a single history entry
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete \"{name}\"?'**
  String queryHistoryConfirmDelete(String name);

  /// Date group label for today's history entries
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get queryHistoryToday;

  /// Date group label for yesterday's history entries
  ///
  /// In en, this message translates to:
  /// **'Yesterday'**
  String get queryHistoryYesterday;

  /// Date group label for history entries from the last 7 days
  ///
  /// In en, this message translates to:
  /// **'Last 7 days'**
  String get queryHistoryLast7Days;

  /// Date group label for history entries older than 7 days
  ///
  /// In en, this message translates to:
  /// **'Older'**
  String get queryHistoryOlder;

  /// Label for saved query history entries
  ///
  /// In en, this message translates to:
  /// **'Saved'**
  String get queryHistorySaved;

  /// Label indicating a history entry was saved manually via Ctrl+S
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get resultHistorySubTabLabel;

  /// No description provided for @dmlCriticalTitle.
  ///
  /// In en, this message translates to:
  /// **'Critical Risk Operation'**
  String get dmlCriticalTitle;

  /// No description provided for @dmlHighWarningTitle.
  ///
  /// In en, this message translates to:
  /// **'High Risk Operation'**
  String get dmlHighWarningTitle;

  /// No description provided for @dmlHighWarningBody.
  ///
  /// In en, this message translates to:
  /// **'This operation will affect all matching rows. Consider adding a LIMIT clause.'**
  String get dmlHighWarningBody;

  /// No description provided for @dmlAddLimit.
  ///
  /// In en, this message translates to:
  /// **'Add LIMIT'**
  String get dmlAddLimit;

  /// No description provided for @dmlConfirmExecute.
  ///
  /// In en, this message translates to:
  /// **'Confirm Execution'**
  String get dmlConfirmExecute;

  /// No description provided for @dmlRiskSummary.
  ///
  /// In en, this message translates to:
  /// **'Risk Summary'**
  String get dmlRiskSummary;

  /// No description provided for @dmlStatementsToExecute.
  ///
  /// In en, this message translates to:
  /// **'Statements to execute:'**
  String get dmlStatementsToExecute;

  /// No description provided for @dmlEstimatedAffectedRows.
  ///
  /// In en, this message translates to:
  /// **'Estimated affected rows: {count}'**
  String dmlEstimatedAffectedRows(Object count);

  /// No description provided for @dmlSqlInjectionDetail.
  ///
  /// In en, this message translates to:
  /// **'SQL Injection: {details}'**
  String dmlSqlInjectionDetail(Object details);

  /// No description provided for @dmlTriggerDeleteWithoutWhere.
  ///
  /// In en, this message translates to:
  /// **'DELETE without WHERE clause'**
  String get dmlTriggerDeleteWithoutWhere;

  /// No description provided for @dmlTriggerUpdateWithoutWhere.
  ///
  /// In en, this message translates to:
  /// **'UPDATE without WHERE clause'**
  String get dmlTriggerUpdateWithoutWhere;

  /// No description provided for @dmlTriggerDropTable.
  ///
  /// In en, this message translates to:
  /// **'DROP TABLE operation'**
  String get dmlTriggerDropTable;

  /// No description provided for @dmlTriggerDropDatabase.
  ///
  /// In en, this message translates to:
  /// **'DROP DATABASE operation'**
  String get dmlTriggerDropDatabase;

  /// No description provided for @dmlTriggerTruncateTable.
  ///
  /// In en, this message translates to:
  /// **'TRUNCATE TABLE operation'**
  String get dmlTriggerTruncateTable;

  /// No description provided for @dmlTriggerDmlWithoutLimit.
  ///
  /// In en, this message translates to:
  /// **'DML without LIMIT clause'**
  String get dmlTriggerDmlWithoutLimit;

  /// No description provided for @dmlTriggerAlterDropColumn.
  ///
  /// In en, this message translates to:
  /// **'ALTER TABLE DROP COLUMN'**
  String get dmlTriggerAlterDropColumn;

  /// No description provided for @dmlTriggerSqlInjection.
  ///
  /// In en, this message translates to:
  /// **'SQL injection pattern detected'**
  String get dmlTriggerSqlInjection;

  /// No description provided for @dropTableDeleteConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to delete table \"{tableName}\"?'**
  String dropTableDeleteConfirmBody(Object tableName);

  /// No description provided for @dropTableDeleteImpact.
  ///
  /// In en, this message translates to:
  /// **'This operation cannot be undone. All data in the table will be permanently deleted.'**
  String get dropTableDeleteImpact;

  /// No description provided for @dropTableCheckingDependencies.
  ///
  /// In en, this message translates to:
  /// **'Checking dependencies...'**
  String get dropTableCheckingDependencies;

  /// No description provided for @dropTableDependencyWarning.
  ///
  /// In en, this message translates to:
  /// **'Dependency Warning'**
  String get dropTableDependencyWarning;

  /// No description provided for @connectionReadOnlyMode.
  ///
  /// In en, this message translates to:
  /// **'Read-Only Mode'**
  String get connectionReadOnlyMode;

  /// No description provided for @connectionReadOnlyModeDesc.
  ///
  /// In en, this message translates to:
  /// **'Prohibit INSERT/UPDATE/DELETE/DDL operations'**
  String get connectionReadOnlyModeDesc;

  /// No description provided for @connectionSshHost.
  ///
  /// In en, this message translates to:
  /// **'SSH Host'**
  String get connectionSshHost;

  /// No description provided for @connectionSshUsername.
  ///
  /// In en, this message translates to:
  /// **'SSH Username'**
  String get connectionSshUsername;

  /// No description provided for @connectionSshPassword.
  ///
  /// In en, this message translates to:
  /// **'SSH Password'**
  String get connectionSshPassword;

  /// No description provided for @connSshHostRequired.
  ///
  /// In en, this message translates to:
  /// **'SSH host is required'**
  String get connSshHostRequired;

  /// No description provided for @commonNavigate.
  ///
  /// In en, this message translates to:
  /// **'Navigate'**
  String get commonNavigate;

  /// No description provided for @resultsSqlStatementLabel.
  ///
  /// In en, this message translates to:
  /// **'SQL statement:'**
  String get resultsSqlStatementLabel;

  /// No description provided for @resultsExecutionSuccess.
  ///
  /// In en, this message translates to:
  /// **'Executed successfully'**
  String get resultsExecutionSuccess;

  /// No description provided for @resultsAffectedRows.
  ///
  /// In en, this message translates to:
  /// **'{count} rows affected'**
  String resultsAffectedRows(Object count);

  /// No description provided for @resultsElapsedMs.
  ///
  /// In en, this message translates to:
  /// **'Elapsed {ms} ms'**
  String resultsElapsedMs(Object ms);

  /// No description provided for @resultsFilterConditions.
  ///
  /// In en, this message translates to:
  /// **'Filter: {count} conditions'**
  String resultsFilterConditions(Object count);

  /// No description provided for @resultsShowingRows.
  ///
  /// In en, this message translates to:
  /// **'Showing {filtered} / {total} rows'**
  String resultsShowingRows(Object filtered, Object total);

  /// No description provided for @resultsClearFilter.
  ///
  /// In en, this message translates to:
  /// **'Clear filters'**
  String get resultsClearFilter;

  /// No description provided for @resultsNoDataGuidance.
  ///
  /// In en, this message translates to:
  /// **'Write a query in the editor and press Ctrl+Enter (or F5) to run it'**
  String get resultsNoDataGuidance;

  /// No description provided for @queryHistoryEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Run a query with Ctrl+Enter or F5 and it will appear here automatically'**
  String get queryHistoryEmptyHint;

  /// No description provided for @safetyExplainWarning.
  ///
  /// In en, this message translates to:
  /// **'Performance Warning'**
  String get safetyExplainWarning;

  /// No description provided for @safetyExplainFullScan.
  ///
  /// In en, this message translates to:
  /// **'Full table scan detected. Estimated {rows} rows to scan.'**
  String safetyExplainFullScan(Object rows);

  /// No description provided for @safetyExecuteAnyway.
  ///
  /// In en, this message translates to:
  /// **'Execute Anyway'**
  String get safetyExecuteAnyway;

  /// No description provided for @safetyCancelAndOptimize.
  ///
  /// In en, this message translates to:
  /// **'Cancel and View Execution Plan'**
  String get safetyCancelAndOptimize;

  /// No description provided for @safetyPreflightTimeout.
  ///
  /// In en, this message translates to:
  /// **'Preflight check timed out. Skipping performance analysis.'**
  String get safetyPreflightTimeout;

  /// No description provided for @dmlAuditBlocked.
  ///
  /// In en, this message translates to:
  /// **'DML operation blocked'**
  String get dmlAuditBlocked;

  /// No description provided for @processListKillQuery.
  ///
  /// In en, this message translates to:
  /// **'Kill Query'**
  String get processListKillQuery;

  /// No description provided for @processListKillConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Kill Process'**
  String get processListKillConfirmTitle;

  /// No description provided for @processListKillConfirm.
  ///
  /// In en, this message translates to:
  /// **'Kill connection {id} ({user}@{host})?'**
  String processListKillConfirm(String id, String user, String host);

  /// No description provided for @processListCopyQuery.
  ///
  /// In en, this message translates to:
  /// **'Copy Query'**
  String get processListCopyQuery;

  /// No description provided for @processListAutoRefresh.
  ///
  /// In en, this message translates to:
  /// **'Auto-refresh'**
  String get processListAutoRefresh;

  /// No description provided for @processListRefreshInterval.
  ///
  /// In en, this message translates to:
  /// **'Refresh interval'**
  String get processListRefreshInterval;

  /// C15 process manager dialog title (Kill Query entry)
  ///
  /// In en, this message translates to:
  /// **'Process Manager'**
  String get processManagerTitle;

  /// No description provided for @processListNoProcesses.
  ///
  /// In en, this message translates to:
  /// **'No active processes'**
  String get processListNoProcesses;

  /// No description provided for @processListNoQueryText.
  ///
  /// In en, this message translates to:
  /// **'No query text'**
  String get processListNoQueryText;

  /// No description provided for @engineStatusTitle.
  ///
  /// In en, this message translates to:
  /// **'Engine Status'**
  String get engineStatusTitle;

  /// No description provided for @engineInnodbStatus.
  ///
  /// In en, this message translates to:
  /// **'InnoDB Status'**
  String get engineInnodbStatus;

  /// No description provided for @engineRowFormat.
  ///
  /// In en, this message translates to:
  /// **'Row Format'**
  String get engineRowFormat;

  /// No description provided for @engineCompression.
  ///
  /// In en, this message translates to:
  /// **'Compression'**
  String get engineCompression;

  /// No description provided for @engineTablespace.
  ///
  /// In en, this message translates to:
  /// **'Tablespace'**
  String get engineTablespace;

  /// No description provided for @replicationRunning.
  ///
  /// In en, this message translates to:
  /// **'Replication: Running'**
  String get replicationRunning;

  /// No description provided for @replicationStopped.
  ///
  /// In en, this message translates to:
  /// **'Replication: Stopped'**
  String get replicationStopped;

  /// No description provided for @replicationLag.
  ///
  /// In en, this message translates to:
  /// **'Lag: {seconds}s'**
  String replicationLag(int seconds);

  /// No description provided for @replicationNotConfigured.
  ///
  /// In en, this message translates to:
  /// **'Replication not configured'**
  String get replicationNotConfigured;

  /// No description provided for @replicationDetailTitle.
  ///
  /// In en, this message translates to:
  /// **'Replication Status'**
  String get replicationDetailTitle;

  /// No description provided for @replicationIoThread.
  ///
  /// In en, this message translates to:
  /// **'IO Thread'**
  String get replicationIoThread;

  /// No description provided for @replicationSqlThread.
  ///
  /// In en, this message translates to:
  /// **'SQL Thread'**
  String get replicationSqlThread;

  /// Button to open a SQLite file via the OS file picker
  ///
  /// In en, this message translates to:
  /// **'Open SQLite File…'**
  String get openSqliteFile;

  /// Section title for recently opened SQLite files
  ///
  /// In en, this message translates to:
  /// **'Recent Files'**
  String get recentFiles;

  /// Empty-state message for the recent files section
  ///
  /// In en, this message translates to:
  /// **'No recent files'**
  String get recentFilesEmpty;

  /// Hint telling the user they can drag a .db file onto the window to open it
  ///
  /// In en, this message translates to:
  /// **'Tip: drag a .db file anywhere to open it'**
  String get dragDropDbHint;

  /// Error message shown when opening a SQLite file fails
  ///
  /// In en, this message translates to:
  /// **'Failed to open SQLite file'**
  String get sqliteOpenError;

  /// No description provided for @sidebarServerGlobal.
  ///
  /// In en, this message translates to:
  /// **'Server'**
  String get sidebarServerGlobal;

  /// No description provided for @sidebarPerformance.
  ///
  /// In en, this message translates to:
  /// **'Performance'**
  String get sidebarPerformance;

  /// No description provided for @sidebarUsers.
  ///
  /// In en, this message translates to:
  /// **'Users'**
  String get sidebarUsers;

  /// No description provided for @serverInfoVersion.
  ///
  /// In en, this message translates to:
  /// **'MySQL {version}'**
  String serverInfoVersion(String version);

  /// No description provided for @serverInfoUptime.
  ///
  /// In en, this message translates to:
  /// **'Uptime: {duration}'**
  String serverInfoUptime(String duration);

  /// No description provided for @serverInfoThreads.
  ///
  /// In en, this message translates to:
  /// **'{active} active / {running} running'**
  String serverInfoThreads(String active, String running);

  /// No description provided for @serverInfoQueries.
  ///
  /// In en, this message translates to:
  /// **'{count} queries'**
  String serverInfoQueries(String count);

  /// No description provided for @serverInfoSlowQueries.
  ///
  /// In en, this message translates to:
  /// **'{count} slow queries'**
  String serverInfoSlowQueries(String count);

  /// No description provided for @serverVarMaxConnections.
  ///
  /// In en, this message translates to:
  /// **'Max Connections'**
  String get serverVarMaxConnections;

  /// No description provided for @serverVarBufferPool.
  ///
  /// In en, this message translates to:
  /// **'Buffer Pool'**
  String get serverVarBufferPool;

  /// No description provided for @serverVarCharset.
  ///
  /// In en, this message translates to:
  /// **'Charset'**
  String get serverVarCharset;

  /// No description provided for @serverStatusUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Server status unavailable'**
  String get serverStatusUnavailable;

  /// No description provided for @processListRefreshLabel.
  ///
  /// In en, this message translates to:
  /// **'Refresh:'**
  String get processListRefreshLabel;

  /// No description provided for @processListRefreshOff.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get processListRefreshOff;

  /// No description provided for @processListMore.
  ///
  /// In en, this message translates to:
  /// **'... and {count} more'**
  String processListMore(num count);

  /// No description provided for @usersNoUsers.
  ///
  /// In en, this message translates to:
  /// **'No users found'**
  String get usersNoUsers;

  /// No description provided for @usersLocked.
  ///
  /// In en, this message translates to:
  /// **'Locked'**
  String get usersLocked;

  /// No description provided for @sidebarDbTableCount.
  ///
  /// In en, this message translates to:
  /// **'{count} tables'**
  String sidebarDbTableCount(num count);

  /// Sidebar node label for MongoDB replication status
  ///
  /// In en, this message translates to:
  /// **'Replication'**
  String get mongoNodeReplication;

  /// Sidebar node label for MongoDB sharding status
  ///
  /// In en, this message translates to:
  /// **'Sharding'**
  String get mongoNodeSharding;

  /// Title for MongoDB validation rules dialog
  ///
  /// In en, this message translates to:
  /// **'Validation Rules'**
  String get mongoValidationRules;

  /// Message shown when MongoDB instance is not a replica set
  ///
  /// In en, this message translates to:
  /// **'Standalone - not part of a replica set'**
  String get mongoReplicationStandalone;

  /// Message shown when MongoDB instance is not a sharded cluster
  ///
  /// In en, this message translates to:
  /// **'Not a sharded cluster'**
  String get mongoShardingNotSharded;

  /// Message shown when collection has no validation rules
  ///
  /// In en, this message translates to:
  /// **'No validation rules'**
  String get mongoValidationNoRules;

  /// Tooltip for the truncation indicator badge on (max) columns whose values are shortened for display
  ///
  /// In en, this message translates to:
  /// **'Value may be truncated (large object type)'**
  String get resultColumnTruncated;

  /// Warning shown when running UPDATE on a Doris Duplicate/Aggregate model table
  ///
  /// In en, this message translates to:
  /// **'Doris tables with a Duplicate or Aggregate model do not support UPDATE; only Unique/Primary Key models do.'**
  String get dorisUpdateGuardMessage;

  /// Label for the Doris table model selector in the create-table dialog
  ///
  /// In en, this message translates to:
  /// **'Table model'**
  String get dorisTableModelLabel;

  /// Doris Duplicate key model option
  ///
  /// In en, this message translates to:
  /// **'Duplicate'**
  String get dorisModelDuplicate;

  /// Doris Unique key model option
  ///
  /// In en, this message translates to:
  /// **'Unique'**
  String get dorisModelUnique;

  /// Doris Primary Key model option
  ///
  /// In en, this message translates to:
  /// **'Primary Key'**
  String get dorisModelPrimaryKey;

  /// Label for the Doris distribution hash column selector
  ///
  /// In en, this message translates to:
  /// **'Hash column'**
  String get dorisHashColumnLabel;

  /// Label for the Doris distribution bucket count
  ///
  /// In en, this message translates to:
  /// **'Buckets'**
  String get dorisBucketsLabel;

  /// Validation message when Unique/Primary Key model is chosen without any key column
  ///
  /// In en, this message translates to:
  /// **'This model requires at least one key column (mark a column as Primary Key)'**
  String get dorisModelNeedsKeyColumn;

  /// Label for the per-value-column aggregation function selector (Doris AGGREGATE model)
  ///
  /// In en, this message translates to:
  /// **'Aggregate function'**
  String get dorisAggregateFunctionLabel;

  /// Doris Aggregate key model option
  ///
  /// In en, this message translates to:
  /// **'Aggregate'**
  String get dorisModelAggregate;

  /// Label for the Doris RANGE partition column selector
  ///
  /// In en, this message translates to:
  /// **'Partition column'**
  String get dorisPartitionColumn;

  /// Label for the Doris partition name input
  ///
  /// In en, this message translates to:
  /// **'Partition name'**
  String get dorisPartitionName;

  /// Label for the Doris partition VALUES LESS THAN boundary input
  ///
  /// In en, this message translates to:
  /// **'Values less than'**
  String get dorisPartitionLessThan;

  /// Button to add a new Doris partition definition
  ///
  /// In en, this message translates to:
  /// **'Add partition'**
  String get dorisAddPartition;

  /// Title of the offline license section in the purchase dialog
  ///
  /// In en, this message translates to:
  /// **'Offline License'**
  String get offlineLicenseTitle;

  /// Instructions for purchasing an offline license
  ///
  /// In en, this message translates to:
  /// **'To upgrade: scan the payment code on our GitHub/Gitee page, then email your machine code and payment screenshot to the author. You will receive a license to import below.'**
  String get offlineLicensePurchaseHint;

  /// Label for the machine code shown in the offline license section
  ///
  /// In en, this message translates to:
  /// **'Machine Code'**
  String get machineCodeLabel;

  /// Shown when the machine code cannot be read
  ///
  /// In en, this message translates to:
  /// **'Unable to read machine code on this device'**
  String get machineCodeUnavailable;

  /// Button to import an offline license
  ///
  /// In en, this message translates to:
  /// **'Import License'**
  String get importLicense;

  /// Hint inside the license import dialog
  ///
  /// In en, this message translates to:
  /// **'Paste the license string, or choose a .dbmlicense file'**
  String get importLicenseHint;

  /// Button to open the purchase page and copy the machine code
  ///
  /// In en, this message translates to:
  /// **'Buy a License'**
  String get buyLicense;

  /// Snackbar after copying the machine code via the buy button
  ///
  /// In en, this message translates to:
  /// **'Machine code copied to clipboard'**
  String get machineCodeCopied;

  /// Button to pick a .dbmlicense file
  ///
  /// In en, this message translates to:
  /// **'Choose File'**
  String get licenseFilePick;

  /// Yearly license type label
  ///
  /// In en, this message translates to:
  /// **'Yearly subscription'**
  String get licenseTypeYearly;

  /// Lifetime license type label
  ///
  /// In en, this message translates to:
  /// **'Lifetime'**
  String get licenseTypeLifetime;

  /// License expiry date line
  ///
  /// In en, this message translates to:
  /// **'Expires: {date}'**
  String licenseExpiresAt(String date);

  /// Button to remove the offline license
  ///
  /// In en, this message translates to:
  /// **'Remove License'**
  String get removeLicense;

  /// Snackbar after a successful license import
  ///
  /// In en, this message translates to:
  /// **'License activated — Pro features unlocked'**
  String get licenseImportSuccess;

  /// License import error: malformed
  ///
  /// In en, this message translates to:
  /// **'Invalid license format'**
  String get licenseErrorInvalid;

  /// License import error: bad signature
  ///
  /// In en, this message translates to:
  /// **'License signature verification failed'**
  String get licenseErrorSignature;

  /// License import error: machine mismatch
  ///
  /// In en, this message translates to:
  /// **'This license is bound to a different machine'**
  String get licenseErrorMachine;

  /// License import error: expired
  ///
  /// In en, this message translates to:
  /// **'This license has expired'**
  String get licenseErrorExpired;

  /// License import error: machine code unavailable
  ///
  /// In en, this message translates to:
  /// **'Cannot read machine code; offline licensing is unavailable on this device'**
  String get licenseErrorNoMachine;

  /// Shows the email of the active offline license
  ///
  /// In en, this message translates to:
  /// **'Licensed to {email}'**
  String licenseActiveInfo(String email);

  /// Copy error to clipboard
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get errorCopy;

  /// Copied to clipboard confirmation
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get errorCopied;

  /// Send error to AI for analysis
  ///
  /// In en, this message translates to:
  /// **'Analyze with AI'**
  String get errorAnalyzeWithAi;

  /// Remaining trial uses for a feature
  ///
  /// In en, this message translates to:
  /// **'{count} trial uses left for {feature}'**
  String trialRemaining(int count, String feature);

  /// Trial quota exhausted for a feature
  ///
  /// In en, this message translates to:
  /// **'{feature} trial is used up'**
  String trialUsedUp(String feature);

  /// Title of the execution center panel
  ///
  /// In en, this message translates to:
  /// **'Execution Center'**
  String get centerTitle;

  /// Tasks tab in execution center
  ///
  /// In en, this message translates to:
  /// **'Tasks'**
  String get centerTabTasks;

  /// Errors tab in execution center
  ///
  /// In en, this message translates to:
  /// **'Errors'**
  String get centerTabErrors;

  /// Clear all errors button
  ///
  /// In en, this message translates to:
  /// **'Clear errors'**
  String get centerClearErrors;

  /// Dismiss an error
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get centerDismissError;

  /// Header prepended when sending an error to AI
  ///
  /// In en, this message translates to:
  /// **'Diagnose this database error: explain the cause and suggest a fix.'**
  String get aiPromptErrorHeader;

  /// No description provided for @commonUndo.
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get commonUndo;

  /// No description provided for @commonDeleteWithCount.
  ///
  /// In en, this message translates to:
  /// **'Delete ({count})'**
  String commonDeleteWithCount(Object count);

  /// No description provided for @aiPanelSessionsDeletedCount.
  ///
  /// In en, this message translates to:
  /// **'Deleted {count} conversations'**
  String aiPanelSessionsDeletedCount(Object count);

  /// No description provided for @aiPanelSessionDeleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted \"{title}\"'**
  String aiPanelSessionDeleted(Object title);

  /// No description provided for @aiPanelSelectDatabaseRequired.
  ///
  /// In en, this message translates to:
  /// **'Please select a database from the dropdown above first.'**
  String get aiPanelSelectDatabaseRequired;

  /// No description provided for @aiPanelMongoExecutionPlan.
  ///
  /// In en, this message translates to:
  /// **'🔍 Mongo Execution Plan'**
  String get aiPanelMongoExecutionPlan;

  /// No description provided for @aiPanelSelectSessions.
  ///
  /// In en, this message translates to:
  /// **'Select Sessions'**
  String get aiPanelSelectSessions;

  /// No description provided for @aiPanelExportTaskCreated.
  ///
  /// In en, this message translates to:
  /// **'Export task created successfully'**
  String get aiPanelExportTaskCreated;

  /// No description provided for @aiPanelDdlOperationCancelled.
  ///
  /// In en, this message translates to:
  /// **'DDL operation cancelled by user.'**
  String get aiPanelDdlOperationCancelled;

  /// No description provided for @aiAssistantOpenTooltip.
  ///
  /// In en, this message translates to:
  /// **'Open AI Assistant'**
  String get aiAssistantOpenTooltip;

  /// No description provided for @schemaImpactRiskLow.
  ///
  /// In en, this message translates to:
  /// **'Low Risk'**
  String get schemaImpactRiskLow;

  /// No description provided for @schemaImpactRiskMedium.
  ///
  /// In en, this message translates to:
  /// **'Medium Risk'**
  String get schemaImpactRiskMedium;

  /// No description provided for @schemaImpactRiskHigh.
  ///
  /// In en, this message translates to:
  /// **'High Risk'**
  String get schemaImpactRiskHigh;

  /// No description provided for @schemaImpactRiskCritical.
  ///
  /// In en, this message translates to:
  /// **'Critical Risk'**
  String get schemaImpactRiskCritical;

  /// No description provided for @schemaImpactTitle.
  ///
  /// In en, this message translates to:
  /// **'Schema Impact Analysis'**
  String get schemaImpactTitle;

  /// No description provided for @schemaImpactSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{type} on `{table}`'**
  String schemaImpactSubtitle(Object table, Object type);

  /// No description provided for @schemaImpactDataLossWarning.
  ///
  /// In en, this message translates to:
  /// **'Data Loss Risk: This operation will permanently delete data.'**
  String get schemaImpactDataLossWarning;

  /// No description provided for @schemaImpactAffectedObjects.
  ///
  /// In en, this message translates to:
  /// **'Affected Objects ({count})'**
  String schemaImpactAffectedObjects(Object count);

  /// No description provided for @schemaImpactWarnings.
  ///
  /// In en, this message translates to:
  /// **'Warnings ({count})'**
  String schemaImpactWarnings(Object count);

  /// No description provided for @schemaImpactRecommendations.
  ///
  /// In en, this message translates to:
  /// **'Recommendations'**
  String get schemaImpactRecommendations;

  /// No description provided for @schemaImpactHideRollbackScript.
  ///
  /// In en, this message translates to:
  /// **'Hide Rollback Script'**
  String get schemaImpactHideRollbackScript;

  /// No description provided for @schemaImpactShowRollbackScript.
  ///
  /// In en, this message translates to:
  /// **'Show Rollback Script'**
  String get schemaImpactShowRollbackScript;

  /// No description provided for @schemaImpactNoRollbackAvailable.
  ///
  /// In en, this message translates to:
  /// **'No rollback available'**
  String get schemaImpactNoRollbackAvailable;

  /// No description provided for @schemaImpactRollbackCaveat.
  ///
  /// In en, this message translates to:
  /// **'Auto-generated rollback is a best-effort draft - column types and constraints may be wrong. Verify before running; data cannot be auto-recovered.'**
  String get schemaImpactRollbackCaveat;

  /// No description provided for @schemaImpactBackupRequired.
  ///
  /// In en, this message translates to:
  /// **'Data backup required before rollback'**
  String get schemaImpactBackupRequired;

  /// No description provided for @schemaImpactConfirmationRequired.
  ///
  /// In en, this message translates to:
  /// **'This operation requires your explicit confirmation before execution.'**
  String get schemaImpactConfirmationRequired;

  /// No description provided for @ddlConfirmDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'DDL Confirmation Required'**
  String get ddlConfirmDialogTitle;

  /// No description provided for @ddlAffectedObjectsCount.
  ///
  /// In en, this message translates to:
  /// **'Affected Objects ({count})'**
  String ddlAffectedObjectsCount(Object count);

  /// No description provided for @ddlExecuteButton.
  ///
  /// In en, this message translates to:
  /// **'Execute DDL'**
  String get ddlExecuteButton;

  /// No description provided for @ddlSqlStatementLabel.
  ///
  /// In en, this message translates to:
  /// **'SQL Statement:'**
  String get ddlSqlStatementLabel;

  /// No description provided for @ddlRiskLevelLabel.
  ///
  /// In en, this message translates to:
  /// **'Risk Level: {level}'**
  String ddlRiskLevelLabel(Object level);

  /// No description provided for @ddlDataLossRiskDetected.
  ///
  /// In en, this message translates to:
  /// **'Data loss risk detected'**
  String get ddlDataLossRiskDetected;

  /// No description provided for @ddlWarningsCount.
  ///
  /// In en, this message translates to:
  /// **'Warnings ({count})'**
  String ddlWarningsCount(Object count);

  /// No description provided for @ddlTypeConfirmationToProceed.
  ///
  /// In en, this message translates to:
  /// **'Type confirmation to proceed'**
  String get ddlTypeConfirmationToProceed;

  /// No description provided for @ddlTypeToConfirmDestructive.
  ///
  /// In en, this message translates to:
  /// **'Type \"{token}\" to confirm this destructive operation:'**
  String ddlTypeToConfirmDestructive(Object token);

  /// No description provided for @commonUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get commonUnknown;

  /// No description provided for @commonDismiss.
  ///
  /// In en, this message translates to:
  /// **'Dismiss'**
  String get commonDismiss;

  /// No description provided for @readOnlyModeBlocked.
  ///
  /// In en, this message translates to:
  /// **'This connection is in read-only mode; write operations are disabled.'**
  String get readOnlyModeBlocked;

  /// No description provided for @dlgFillVariables.
  ///
  /// In en, this message translates to:
  /// **'Fill in Variables'**
  String get dlgFillVariables;

  /// No description provided for @dlgVariableRequired.
  ///
  /// In en, this message translates to:
  /// **'Please enter {variable}'**
  String dlgVariableRequired(String variable);

  /// No description provided for @dlgEditTrigger.
  ///
  /// In en, this message translates to:
  /// **'Edit Trigger'**
  String get dlgEditTrigger;

  /// No description provided for @dlgCreateTrigger.
  ///
  /// In en, this message translates to:
  /// **'Create Trigger'**
  String get dlgCreateTrigger;

  /// No description provided for @triggerLoadTablesFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load tables: {error}'**
  String triggerLoadTablesFailed(String error);

  /// No description provided for @triggerSelectTableRequired.
  ///
  /// In en, this message translates to:
  /// **'Please select a table'**
  String get triggerSelectTableRequired;

  /// No description provided for @triggerSelectEventRequired.
  ///
  /// In en, this message translates to:
  /// **'Please select at least one event'**
  String get triggerSelectEventRequired;

  /// No description provided for @triggerUpdated.
  ///
  /// In en, this message translates to:
  /// **'Trigger updated successfully'**
  String get triggerUpdated;

  /// No description provided for @triggerCreated.
  ///
  /// In en, this message translates to:
  /// **'Trigger created successfully'**
  String get triggerCreated;

  /// No description provided for @triggerSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to save trigger: {error}'**
  String triggerSaveFailed(String error);

  /// No description provided for @triggerNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Trigger Name'**
  String get triggerNameLabel;

  /// No description provided for @triggerNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Trigger name is required'**
  String get triggerNameRequired;

  /// No description provided for @triggerNameInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid trigger name format'**
  String get triggerNameInvalid;

  /// No description provided for @triggerTimingLabel.
  ///
  /// In en, this message translates to:
  /// **'Timing'**
  String get triggerTimingLabel;

  /// No description provided for @triggerEventLabel.
  ///
  /// In en, this message translates to:
  /// **'Event'**
  String get triggerEventLabel;

  /// No description provided for @triggerTableLabel.
  ///
  /// In en, this message translates to:
  /// **'Table'**
  String get triggerTableLabel;

  /// No description provided for @triggerSelectTableHint.
  ///
  /// In en, this message translates to:
  /// **'Select a table'**
  String get triggerSelectTableHint;

  /// No description provided for @triggerBodyLabel.
  ///
  /// In en, this message translates to:
  /// **'Trigger Body'**
  String get triggerBodyLabel;

  /// No description provided for @triggerBodyHint.
  ///
  /// In en, this message translates to:
  /// **'Enter trigger body (SQL statements)\nExample:\nSET NEW.updated_at = NOW();'**
  String get triggerBodyHint;

  /// No description provided for @triggerCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =1{1 trigger} other{{count} triggers}}'**
  String triggerCount(int count);

  /// No description provided for @dlgExecutionResult.
  ///
  /// In en, this message translates to:
  /// **'Execution Result'**
  String get dlgExecutionResult;

  /// No description provided for @dlgExecuteRoutine.
  ///
  /// In en, this message translates to:
  /// **'Execute {type}'**
  String dlgExecuteRoutine(String type);

  /// No description provided for @dlgRoutineName.
  ///
  /// In en, this message translates to:
  /// **'Name: {name}'**
  String dlgRoutineName(String name);

  /// No description provided for @dlgRoutineType.
  ///
  /// In en, this message translates to:
  /// **'Type: {type}'**
  String dlgRoutineType(String type);

  /// No description provided for @dlgRoutineReturnType.
  ///
  /// In en, this message translates to:
  /// **'Return Type: {type}'**
  String dlgRoutineReturnType(String type);

  /// No description provided for @dlgParameters.
  ///
  /// In en, this message translates to:
  /// **'Parameters'**
  String get dlgParameters;

  /// No description provided for @dlgRoutineNoParams.
  ///
  /// In en, this message translates to:
  /// **'This procedure/function requires no parameters'**
  String get dlgRoutineNoParams;

  /// No description provided for @dlgOutputParam.
  ///
  /// In en, this message translates to:
  /// **'Output Parameter'**
  String get dlgOutputParam;

  /// No description provided for @dlgReturnValueLabel.
  ///
  /// In en, this message translates to:
  /// **'Return Value:'**
  String get dlgReturnValueLabel;

  /// No description provided for @dlgRowsAffected.
  ///
  /// In en, this message translates to:
  /// **'Rows affected: {count}'**
  String dlgRowsAffected(int count);

  /// No description provided for @dlgEditRoutine.
  ///
  /// In en, this message translates to:
  /// **'Edit {type}'**
  String dlgEditRoutine(String type);

  /// No description provided for @routineParameterCount.
  ///
  /// In en, this message translates to:
  /// **'{count, plural, =0{No parameters} =1{1 parameter} other{{count} parameters}}'**
  String routineParameterCount(int count);

  /// No description provided for @routineDeleteConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Delete {type} \"{name}\"?'**
  String routineDeleteConfirmation(String type, String name);

  /// No description provided for @routineListTitle.
  ///
  /// In en, this message translates to:
  /// **'Procedures & Functions'**
  String get routineListTitle;

  /// No description provided for @routineDefinitionTitle.
  ///
  /// In en, this message translates to:
  /// **'{type} Definition'**
  String routineDefinitionTitle(String type);

  /// No description provided for @queryExecutionPlan.
  ///
  /// In en, this message translates to:
  /// **'Query Execution Plan'**
  String get queryExecutionPlan;

  /// No description provided for @dlgCreateRoutine.
  ///
  /// In en, this message translates to:
  /// **'Create {type}'**
  String dlgCreateRoutine(String type);

  /// No description provided for @dlgNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Name is required'**
  String get dlgNameRequired;

  /// No description provided for @dlgRoutineNameInvalid.
  ///
  /// In en, this message translates to:
  /// **'Name can only contain letters, digits and underscores, and cannot start with a digit'**
  String get dlgRoutineNameInvalid;

  /// No description provided for @dlgReturnTypeRequired.
  ///
  /// In en, this message translates to:
  /// **'Please select a return type'**
  String get dlgReturnTypeRequired;

  /// No description provided for @dlgSqlCode.
  ///
  /// In en, this message translates to:
  /// **'SQL Code'**
  String get dlgSqlCode;

  /// No description provided for @dlgRoutineProcedure.
  ///
  /// In en, this message translates to:
  /// **'Stored Procedure'**
  String get dlgRoutineProcedure;

  /// No description provided for @dlgRoutineFunction.
  ///
  /// In en, this message translates to:
  /// **'Function'**
  String get dlgRoutineFunction;

  /// No description provided for @commonUpdate.
  ///
  /// In en, this message translates to:
  /// **'Update'**
  String get commonUpdate;

  /// No description provided for @commonCreate.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get commonCreate;

  /// No description provided for @auditLogTitle.
  ///
  /// In en, this message translates to:
  /// **'Query Audit Log'**
  String get auditLogTitle;

  /// No description provided for @auditLogAllStatus.
  ///
  /// In en, this message translates to:
  /// **'All Status'**
  String get auditLogAllStatus;

  /// No description provided for @auditLogAll.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get auditLogAll;

  /// No description provided for @auditLogTime.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get auditLogTime;

  /// No description provided for @auditLogDuration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get auditLogDuration;

  /// No description provided for @auditLogRows.
  ///
  /// In en, this message translates to:
  /// **'Rows'**
  String get auditLogRows;

  /// No description provided for @auditLogStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get auditLogStatus;

  /// No description provided for @auditLogEmpty.
  ///
  /// In en, this message translates to:
  /// **'No audit logs yet'**
  String get auditLogEmpty;

  /// No description provided for @auditLogEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Execute queries to start recording logs'**
  String get auditLogEmptyHint;

  /// No description provided for @auditLogTotal.
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get auditLogTotal;

  /// No description provided for @auditLogWrite.
  ///
  /// In en, this message translates to:
  /// **'Write'**
  String get auditLogWrite;

  /// No description provided for @auditLogAvgTime.
  ///
  /// In en, this message translates to:
  /// **'Avg Time'**
  String get auditLogAvgTime;

  /// No description provided for @auditLogClearTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear Audit Logs'**
  String get auditLogClearTitle;

  /// No description provided for @auditLogClearConfirm.
  ///
  /// In en, this message translates to:
  /// **'Are you sure you want to clear all audit logs? This action cannot be undone.'**
  String get auditLogClearConfirm;

  /// No description provided for @auditLogClear.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get auditLogClear;

  /// No description provided for @piiMaskingTitle.
  ///
  /// In en, this message translates to:
  /// **'PII Data Masking'**
  String get piiMaskingTitle;

  /// No description provided for @piiMaskingEnable.
  ///
  /// In en, this message translates to:
  /// **'Enable PII Masking'**
  String get piiMaskingEnable;

  /// No description provided for @piiMaskingEnableDesc.
  ///
  /// In en, this message translates to:
  /// **'Automatically mask sensitive data in query results'**
  String get piiMaskingEnableDesc;

  /// No description provided for @piiMaskingTypes.
  ///
  /// In en, this message translates to:
  /// **'Sensitive Data Types'**
  String get piiMaskingTypes;

  /// No description provided for @piiTypeEmail.
  ///
  /// In en, this message translates to:
  /// **'Email Addresses'**
  String get piiTypeEmail;

  /// No description provided for @piiTypePhone.
  ///
  /// In en, this message translates to:
  /// **'Phone Numbers'**
  String get piiTypePhone;

  /// No description provided for @piiTypeIdCard.
  ///
  /// In en, this message translates to:
  /// **'ID Cards'**
  String get piiTypeIdCard;

  /// No description provided for @piiTypeCreditCard.
  ///
  /// In en, this message translates to:
  /// **'Credit Cards'**
  String get piiTypeCreditCard;

  /// No description provided for @piiTypeBankCard.
  ///
  /// In en, this message translates to:
  /// **'Bank Accounts'**
  String get piiTypeBankCard;

  /// No description provided for @piiTypePassword.
  ///
  /// In en, this message translates to:
  /// **'Passwords'**
  String get piiTypePassword;

  /// No description provided for @piiTypeIpAddress.
  ///
  /// In en, this message translates to:
  /// **'IP Addresses'**
  String get piiTypeIpAddress;

  /// No description provided for @shortcutNoMatching.
  ///
  /// In en, this message translates to:
  /// **'No matching shortcuts'**
  String get shortcutNoMatching;

  /// No description provided for @shortcutPressEscToClose.
  ///
  /// In en, this message translates to:
  /// **'Press ESC to close'**
  String get shortcutPressEscToClose;

  /// No description provided for @indexTypePrimary.
  ///
  /// In en, this message translates to:
  /// **'Primary'**
  String get indexTypePrimary;

  /// No description provided for @performanceAnalyzerWeeklyReportTitle.
  ///
  /// In en, this message translates to:
  /// **'Weekly slow query reports'**
  String get performanceAnalyzerWeeklyReportTitle;

  /// No description provided for @performanceAnalyzerWeeklyReportDesc.
  ///
  /// In en, this message translates to:
  /// **'Get top-10 slow queries with EXPLAIN analysis every Monday'**
  String get performanceAnalyzerWeeklyReportDesc;

  /// No description provided for @performanceAnalyzerLearnMore.
  ///
  /// In en, this message translates to:
  /// **'Learn more'**
  String get performanceAnalyzerLearnMore;

  /// No description provided for @backupListLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading backup list...'**
  String get backupListLoading;

  /// No description provided for @dbPropertiesTitle.
  ///
  /// In en, this message translates to:
  /// **'Database Properties - {name}'**
  String dbPropertiesTitle(String name);

  /// No description provided for @dbPropertyName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get dbPropertyName;

  /// No description provided for @dbPropertyCharset.
  ///
  /// In en, this message translates to:
  /// **'Charset'**
  String get dbPropertyCharset;

  /// No description provided for @dbPropertyCollation.
  ///
  /// In en, this message translates to:
  /// **'Collation'**
  String get dbPropertyCollation;

  /// No description provided for @dbPropertySize.
  ///
  /// In en, this message translates to:
  /// **'Size'**
  String get dbPropertySize;

  /// No description provided for @dbPropertyTableCount.
  ///
  /// In en, this message translates to:
  /// **'Tables'**
  String get dbPropertyTableCount;

  /// No description provided for @dbPropertyViewCount.
  ///
  /// In en, this message translates to:
  /// **'Views'**
  String get dbPropertyViewCount;

  /// No description provided for @dbPropertyRoutineCount.
  ///
  /// In en, this message translates to:
  /// **'Procedures/Functions'**
  String get dbPropertyRoutineCount;

  /// No description provided for @exportFormatLabel.
  ///
  /// In en, this message translates to:
  /// **'Export Format'**
  String get exportFormatLabel;

  /// No description provided for @exportRowCount.
  ///
  /// In en, this message translates to:
  /// **'{count} rows total'**
  String exportRowCount(int count);

  /// No description provided for @taskCreateExportFilter.
  ///
  /// In en, this message translates to:
  /// **'Filter'**
  String get taskCreateExportFilter;

  /// No description provided for @taskCreateExportEstRows.
  ///
  /// In en, this message translates to:
  /// **'Estimated Rows'**
  String get taskCreateExportEstRows;

  /// No description provided for @taskCreateExportValidating.
  ///
  /// In en, this message translates to:
  /// **'Validating...'**
  String get taskCreateExportValidating;

  /// No description provided for @taskCreateExportSaveDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Select save location for export file'**
  String get taskCreateExportSaveDialogTitle;

  /// No description provided for @taskValidationPathNotExists.
  ///
  /// In en, this message translates to:
  /// **'Directory does not exist: {path}'**
  String taskValidationPathNotExists(String path);

  /// No description provided for @taskCreateExportDesc.
  ///
  /// In en, this message translates to:
  /// **'Export {table}'**
  String taskCreateExportDesc(String table);

  /// No description provided for @taskCreateExportDescFiltered.
  ///
  /// In en, this message translates to:
  /// **'Export {table} (filtered)'**
  String taskCreateExportDescFiltered(String table);

  /// No description provided for @sqliteConnectionEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit SQLite Connection'**
  String get sqliteConnectionEditTitle;

  /// No description provided for @sqliteConnectionNewTitle.
  ///
  /// In en, this message translates to:
  /// **'New SQLite Connection'**
  String get sqliteConnectionNewTitle;

  /// No description provided for @createSuperTableTitle.
  ///
  /// In en, this message translates to:
  /// **'Create SuperTable'**
  String get createSuperTableTitle;

  /// No description provided for @importWizardTitle.
  ///
  /// In en, this message translates to:
  /// **'Data Import Wizard'**
  String get importWizardTitle;

  /// No description provided for @dbCreateSuccess.
  ///
  /// In en, this message translates to:
  /// **'Database \"{name}\" created successfully'**
  String dbCreateSuccess(String name);

  /// No description provided for @dbCreateFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to create database'**
  String get dbCreateFailed;

  /// No description provided for @dbCreateError.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String dbCreateError(String error);

  /// No description provided for @dbOperationCannotBeUndone.
  ///
  /// In en, this message translates to:
  /// **'This operation cannot be undone!'**
  String get dbOperationCannotBeUndone;

  /// No description provided for @dropTablePermanentWarning.
  ///
  /// In en, this message translates to:
  /// **'Table \"{table}\" and all its data will be permanently deleted.'**
  String dropTablePermanentWarning(String table);

  /// No description provided for @dropTableDataLossWarning.
  ///
  /// In en, this message translates to:
  /// **'This operation cannot be undone! All data in this table will be permanently lost.'**
  String get dropTableDataLossWarning;

  /// No description provided for @objectTypeTable.
  ///
  /// In en, this message translates to:
  /// **'table'**
  String get objectTypeTable;

  /// No description provided for @objectTypeView.
  ///
  /// In en, this message translates to:
  /// **'view'**
  String get objectTypeView;

  /// No description provided for @commonRemove.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get commonRemove;

  /// No description provided for @commonRequired.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get commonRequired;

  /// No description provided for @commonInvalidIdentifier.
  ///
  /// In en, this message translates to:
  /// **'Invalid identifier'**
  String get commonInvalidIdentifier;

  /// No description provided for @mongoValidationJsonObject.
  ///
  /// In en, this message translates to:
  /// **'JSON must be an object'**
  String get mongoValidationJsonObject;

  /// No description provided for @mongoValidationInvalidJson.
  ///
  /// In en, this message translates to:
  /// **'Invalid JSON: {error}'**
  String mongoValidationInvalidJson(String error);

  /// No description provided for @settingsAutoLimitEnabledDesc.
  ///
  /// In en, this message translates to:
  /// **'Automatically add LIMIT to SELECT queries'**
  String get settingsAutoLimitEnabledDesc;

  /// No description provided for @sqliteConnectionInfo.
  ///
  /// In en, this message translates to:
  /// **'Connection Info'**
  String get sqliteConnectionInfo;

  /// No description provided for @sqliteNameHint.
  ///
  /// In en, this message translates to:
  /// **'My SQLite Database'**
  String get sqliteNameHint;

  /// No description provided for @connectionDirNotExists.
  ///
  /// In en, this message translates to:
  /// **'Directory does not exist'**
  String get connectionDirNotExists;

  /// No description provided for @indexSelectColumnRequired.
  ///
  /// In en, this message translates to:
  /// **'Please select at least one column'**
  String get indexSelectColumnRequired;

  /// No description provided for @indexCreateFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to create index: {error}'**
  String indexCreateFailed(String error);

  /// No description provided for @indexUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to update index: {error}'**
  String indexUpdateFailed(String error);

  /// No description provided for @indexNameRequired.
  ///
  /// In en, this message translates to:
  /// **'Index name is required'**
  String get indexNameRequired;

  /// No description provided for @superTableTags.
  ///
  /// In en, this message translates to:
  /// **'Tags'**
  String get superTableTags;

  /// No description provided for @superTableCreated.
  ///
  /// In en, this message translates to:
  /// **'SuperTable created successfully'**
  String get superTableCreated;

  /// No description provided for @redisLibNameCodeRequired.
  ///
  /// In en, this message translates to:
  /// **'Library name and code are required'**
  String get redisLibNameCodeRequired;

  /// No description provided for @redisAdapterNotAvailable.
  ///
  /// In en, this message translates to:
  /// **'Redis adapter not available'**
  String get redisAdapterNotAvailable;

  /// No description provided for @redisLibraryCreated.
  ///
  /// In en, this message translates to:
  /// **'Function library created successfully'**
  String get redisLibraryCreated;

  /// No description provided for @redisLibraryCreateFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to create library: {error}'**
  String redisLibraryCreateFailed(String error);

  /// No description provided for @redisLibraryUsageHint.
  ///
  /// In en, this message translates to:
  /// **'Used in #!lua name=<library>'**
  String get redisLibraryUsageHint;

  /// No description provided for @redisInsertExample.
  ///
  /// In en, this message translates to:
  /// **'Insert Example'**
  String get redisInsertExample;

  /// No description provided for @redisCreateLibrary.
  ///
  /// In en, this message translates to:
  /// **'Create Library'**
  String get redisCreateLibrary;

  /// No description provided for @redisKeyLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load key data: {error}'**
  String redisKeyLoadFailed(String error);

  /// No description provided for @redisKeyUpdated.
  ///
  /// In en, this message translates to:
  /// **'Key updated successfully'**
  String get redisKeyUpdated;

  /// No description provided for @redisKeySaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to save key: {error}'**
  String redisKeySaveFailed(String error);

  /// No description provided for @redisKeySaveChanges.
  ///
  /// In en, this message translates to:
  /// **'Save Changes'**
  String get redisKeySaveChanges;

  /// No description provided for @serverConnectTitle.
  ///
  /// In en, this message translates to:
  /// **'Connect to Server'**
  String get serverConnectTitle;

  /// No description provided for @serverConnectUrl.
  ///
  /// In en, this message translates to:
  /// **'Server URL'**
  String get serverConnectUrl;

  /// No description provided for @serverUrlRequired.
  ///
  /// In en, this message translates to:
  /// **'Server URL is required'**
  String get serverUrlRequired;

  /// No description provided for @serverUrlInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid URL (e.g. https://myserver:3000)'**
  String get serverUrlInvalid;

  /// No description provided for @serverConnectEmail.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get serverConnectEmail;

  /// No description provided for @serverEmailRequired.
  ///
  /// In en, this message translates to:
  /// **'Email is required'**
  String get serverEmailRequired;

  /// No description provided for @serverEmailInvalid.
  ///
  /// In en, this message translates to:
  /// **'Invalid email'**
  String get serverEmailInvalid;

  /// No description provided for @serverPasswordRequired.
  ///
  /// In en, this message translates to:
  /// **'Password is required'**
  String get serverPasswordRequired;

  /// No description provided for @mongoValidationFixErrors.
  ///
  /// In en, this message translates to:
  /// **'Please fix JSON errors before applying'**
  String get mongoValidationFixErrors;

  /// No description provided for @mongoValidationApplied.
  ///
  /// In en, this message translates to:
  /// **'Validation rules applied successfully'**
  String get mongoValidationApplied;

  /// No description provided for @mongoValidationRemoved.
  ///
  /// In en, this message translates to:
  /// **'Validation rules removed'**
  String get mongoValidationRemoved;

  /// C17 mongo validation viewer row: validationLevel
  ///
  /// In en, this message translates to:
  /// **'Validation Level'**
  String get mongoValidationLevel;

  /// C17 mongo validation viewer row: validationAction
  ///
  /// In en, this message translates to:
  /// **'Validation Action'**
  String get mongoValidationAction;

  /// No description provided for @mongoValidationApplyFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to apply validation rules: {error}'**
  String mongoValidationApplyFailed(String error);

  /// No description provided for @indexSelectColumns.
  ///
  /// In en, this message translates to:
  /// **'Select Columns'**
  String get indexSelectColumns;

  /// No description provided for @redisLibraryTitle.
  ///
  /// In en, this message translates to:
  /// **'Create Function Library'**
  String get redisLibraryTitle;

  /// No description provided for @redisLibraryNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Library Name'**
  String get redisLibraryNameLabel;

  /// No description provided for @redisLibraryCreateFailedSyntax.
  ///
  /// In en, this message translates to:
  /// **'Failed to create library (requires Redis 7.0+, check syntax)'**
  String get redisLibraryCreateFailedSyntax;

  /// No description provided for @redisLuaCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Lua Code'**
  String get redisLuaCodeLabel;

  /// No description provided for @redisReplaceExisting.
  ///
  /// In en, this message translates to:
  /// **'Replace existing library with the same name (FUNCTION LOAD REPLACE)'**
  String get redisReplaceExisting;

  /// No description provided for @redisLibraryInfoText.
  ///
  /// In en, this message translates to:
  /// **'Library name is written into the #!lua shebang automatically. Lua code should contain redis.register_function() calls. Do not write the shebang yourself.'**
  String get redisLibraryInfoText;

  /// No description provided for @superTableCreateFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to create SuperTable'**
  String get superTableCreateFailed;

  /// No description provided for @superTableColumns.
  ///
  /// In en, this message translates to:
  /// **'Columns'**
  String get superTableColumns;

  /// No description provided for @errorTitle.
  ///
  /// In en, this message translates to:
  /// **'An error occurred'**
  String get errorTitle;

  /// No description provided for @errorDescriptionLabel.
  ///
  /// In en, this message translates to:
  /// **'Error details:'**
  String get errorDescriptionLabel;

  /// No description provided for @errorStackLabel.
  ///
  /// In en, this message translates to:
  /// **'Stack trace:'**
  String get errorStackLabel;

  /// No description provided for @columnFilterTypeNumeric.
  ///
  /// In en, this message translates to:
  /// **'Numeric'**
  String get columnFilterTypeNumeric;

  /// No description provided for @columnFilterTypeDateTime.
  ///
  /// In en, this message translates to:
  /// **'Date/Time'**
  String get columnFilterTypeDateTime;

  /// No description provided for @columnFilterTypeText.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get columnFilterTypeText;

  /// No description provided for @columnFilterPlaceholderNumeric.
  ///
  /// In en, this message translates to:
  /// **'Enter a number'**
  String get columnFilterPlaceholderNumeric;

  /// No description provided for @columnFilterPlaceholderDateTime.
  ///
  /// In en, this message translates to:
  /// **'Enter date (e.g., 2024-01-01)'**
  String get columnFilterPlaceholderDateTime;

  /// No description provided for @columnFilterPlaceholderText.
  ///
  /// In en, this message translates to:
  /// **'Enter text'**
  String get columnFilterPlaceholderText;

  /// No description provided for @columnFilterFor.
  ///
  /// In en, this message translates to:
  /// **'Filter: {columnName}'**
  String columnFilterFor(String columnName);

  /// No description provided for @columnFilterActive.
  ///
  /// In en, this message translates to:
  /// **'{count} active filter conditions'**
  String columnFilterActive(int count);

  /// No description provided for @columnFilterRowCount.
  ///
  /// In en, this message translates to:
  /// **'{filtered} / {total} rows'**
  String columnFilterRowCount(String filtered, String total);

  /// No description provided for @filterOpEquals.
  ///
  /// In en, this message translates to:
  /// **'equals'**
  String get filterOpEquals;

  /// No description provided for @filterOpNotEquals.
  ///
  /// In en, this message translates to:
  /// **'not equals'**
  String get filterOpNotEquals;

  /// No description provided for @filterOpContains.
  ///
  /// In en, this message translates to:
  /// **'contains'**
  String get filterOpContains;

  /// No description provided for @filterOpNotContains.
  ///
  /// In en, this message translates to:
  /// **'not contains'**
  String get filterOpNotContains;

  /// No description provided for @filterOpStartsWith.
  ///
  /// In en, this message translates to:
  /// **'starts with'**
  String get filterOpStartsWith;

  /// No description provided for @filterOpEndsWith.
  ///
  /// In en, this message translates to:
  /// **'ends with'**
  String get filterOpEndsWith;

  /// No description provided for @filterOpGreaterThan.
  ///
  /// In en, this message translates to:
  /// **'greater than'**
  String get filterOpGreaterThan;

  /// No description provided for @filterOpGreaterThanOrEqual.
  ///
  /// In en, this message translates to:
  /// **'greater than or equal'**
  String get filterOpGreaterThanOrEqual;

  /// No description provided for @filterOpLessThan.
  ///
  /// In en, this message translates to:
  /// **'less than'**
  String get filterOpLessThan;

  /// No description provided for @filterOpLessThanOrEqual.
  ///
  /// In en, this message translates to:
  /// **'less than or equal'**
  String get filterOpLessThanOrEqual;

  /// No description provided for @filterOpBetween.
  ///
  /// In en, this message translates to:
  /// **'between'**
  String get filterOpBetween;

  /// No description provided for @filterOpIsNull.
  ///
  /// In en, this message translates to:
  /// **'is null'**
  String get filterOpIsNull;

  /// No description provided for @filterOpIsNotNull.
  ///
  /// In en, this message translates to:
  /// **'is not null'**
  String get filterOpIsNotNull;

  /// No description provided for @filterOpIsEmpty.
  ///
  /// In en, this message translates to:
  /// **'is empty'**
  String get filterOpIsEmpty;

  /// No description provided for @filterOpIsNotEmpty.
  ///
  /// In en, this message translates to:
  /// **'is not empty'**
  String get filterOpIsNotEmpty;

  /// No description provided for @tableNoData.
  ///
  /// In en, this message translates to:
  /// **'No data'**
  String get tableNoData;

  /// No description provided for @tableRowCountTotal.
  ///
  /// In en, this message translates to:
  /// **'{count} total rows'**
  String tableRowCountTotal(String count);

  /// No description provided for @tableLargeDatasetHint.
  ///
  /// In en, this message translates to:
  /// **'(Large dataset, scroll to load more)'**
  String get tableLargeDatasetHint;

  /// No description provided for @tableRowRange.
  ///
  /// In en, this message translates to:
  /// **'{start}-{end} / {total} rows'**
  String tableRowRange(String start, String end, String total);

  /// No description provided for @importWizStepSelectFile.
  ///
  /// In en, this message translates to:
  /// **'Select File'**
  String get importWizStepSelectFile;

  /// No description provided for @importWizStepAnalyzeFile.
  ///
  /// In en, this message translates to:
  /// **'Analyze File'**
  String get importWizStepAnalyzeFile;

  /// No description provided for @importWizStepColumnMapping.
  ///
  /// In en, this message translates to:
  /// **'Column Mapping'**
  String get importWizStepColumnMapping;

  /// No description provided for @importWizStepPreviewPII.
  ///
  /// In en, this message translates to:
  /// **'Preview & PII'**
  String get importWizStepPreviewPII;

  /// No description provided for @importWizStepConfirmImport.
  ///
  /// In en, this message translates to:
  /// **'Confirm Import'**
  String get importWizStepConfirmImport;

  /// No description provided for @importWizStepOf.
  ///
  /// In en, this message translates to:
  /// **'Step {current} of {total}: {title}'**
  String importWizStepOf(String current, String total, String title);

  /// No description provided for @importWizTargetDatabase.
  ///
  /// In en, this message translates to:
  /// **'Target Database'**
  String get importWizTargetDatabase;

  /// No description provided for @importWizSelectDatabase.
  ///
  /// In en, this message translates to:
  /// **'Select database'**
  String get importWizSelectDatabase;

  /// No description provided for @importWizTargetTableOptional.
  ///
  /// In en, this message translates to:
  /// **'Target Table (optional)'**
  String get importWizTargetTableOptional;

  /// No description provided for @importWizLetAiInfer.
  ///
  /// In en, this message translates to:
  /// **'-- Let AI infer table name --'**
  String get importWizLetAiInfer;

  /// No description provided for @importWizChooseFile.
  ///
  /// In en, this message translates to:
  /// **'Click to select file or drag here'**
  String get importWizChooseFile;

  /// No description provided for @importWizChangeFile.
  ///
  /// In en, this message translates to:
  /// **'Change file'**
  String get importWizChangeFile;

  /// No description provided for @importWizSupportedFormats.
  ///
  /// In en, this message translates to:
  /// **'Supports CSV, JSON, Excel, TSV formats'**
  String get importWizSupportedFormats;

  /// No description provided for @importWizFileUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get importWizFileUnknown;

  /// No description provided for @importWizAiAnalyzing.
  ///
  /// In en, this message translates to:
  /// **'AI is analyzing file...'**
  String get importWizAiAnalyzing;

  /// No description provided for @importWizDetectingFormat.
  ///
  /// In en, this message translates to:
  /// **'Detecting format, encoding, field types...'**
  String get importWizDetectingFormat;

  /// No description provided for @importWizFileAnalysisResult.
  ///
  /// In en, this message translates to:
  /// **'File Analysis Result'**
  String get importWizFileAnalysisResult;

  /// No description provided for @importWizFormat.
  ///
  /// In en, this message translates to:
  /// **'Format'**
  String get importWizFormat;

  /// No description provided for @importWizEncoding.
  ///
  /// In en, this message translates to:
  /// **'Encoding'**
  String get importWizEncoding;

  /// No description provided for @importWizFieldCount.
  ///
  /// In en, this message translates to:
  /// **'Fields'**
  String get importWizFieldCount;

  /// No description provided for @importWizEstimatedRows.
  ///
  /// In en, this message translates to:
  /// **'Est. rows'**
  String get importWizEstimatedRows;

  /// No description provided for @importWizFileSize.
  ///
  /// In en, this message translates to:
  /// **'File size'**
  String get importWizFileSize;

  /// No description provided for @importWizDelimiter.
  ///
  /// In en, this message translates to:
  /// **'Delimiter'**
  String get importWizDelimiter;

  /// No description provided for @importWizDetectedFields.
  ///
  /// In en, this message translates to:
  /// **'Detected Fields'**
  String get importWizDetectedFields;

  /// No description provided for @importWizAiSuggestion.
  ///
  /// In en, this message translates to:
  /// **'AI Suggestion'**
  String get importWizAiSuggestion;

  /// No description provided for @importWizTargetTableName.
  ///
  /// In en, this message translates to:
  /// **'Target table: {tableName}'**
  String importWizTargetTableName(String tableName);

  /// No description provided for @importWizNoAnalysisResult.
  ///
  /// In en, this message translates to:
  /// **'No analysis result'**
  String get importWizNoAnalysisResult;

  /// No description provided for @importWizSelectFileFirst.
  ///
  /// In en, this message translates to:
  /// **'Please select a file first'**
  String get importWizSelectFileFirst;

  /// No description provided for @importWizNoColumnMapping.
  ///
  /// In en, this message translates to:
  /// **'No column mapping'**
  String get importWizNoColumnMapping;

  /// No description provided for @importWizGeneratingMapping.
  ///
  /// In en, this message translates to:
  /// **'Generating mapping...'**
  String get importWizGeneratingMapping;

  /// No description provided for @importWizColumnMappingConfig.
  ///
  /// In en, this message translates to:
  /// **'Column Mapping Configuration'**
  String get importWizColumnMappingConfig;

  /// No description provided for @importWizColumnsMapped.
  ///
  /// In en, this message translates to:
  /// **'{mapped}/{total} columns mapped'**
  String importWizColumnsMapped(String mapped, String total);

  /// No description provided for @importWizMappingDescription.
  ///
  /// In en, this message translates to:
  /// **'Map file columns to database table columns. Select \"Skip\" to skip a column.'**
  String get importWizMappingDescription;

  /// No description provided for @importWizFileColumn.
  ///
  /// In en, this message translates to:
  /// **'File Column'**
  String get importWizFileColumn;

  /// No description provided for @importWizDatabaseColumn.
  ///
  /// In en, this message translates to:
  /// **'Database Column'**
  String get importWizDatabaseColumn;

  /// No description provided for @importWizType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get importWizType;

  /// No description provided for @importWizPiiDetection.
  ///
  /// In en, this message translates to:
  /// **'PII Sensitive Data Detection'**
  String get importWizPiiDetection;

  /// No description provided for @importWizPiiDetectionMessage.
  ///
  /// In en, this message translates to:
  /// **'The following sensitive fields were detected. Please confirm whether to continue the import:'**
  String get importWizPiiDetectionMessage;

  /// No description provided for @importWizPiiAcknowledge.
  ///
  /// In en, this message translates to:
  /// **'I understand, continue import'**
  String get importWizPiiAcknowledge;

  /// No description provided for @importWizDataPreview.
  ///
  /// In en, this message translates to:
  /// **'Data Preview'**
  String get importWizDataPreview;

  /// No description provided for @importWizWarnings.
  ///
  /// In en, this message translates to:
  /// **'{count} warnings'**
  String importWizWarnings(String count);

  /// No description provided for @importWizFirstRows.
  ///
  /// In en, this message translates to:
  /// **'First {count} rows'**
  String importWizFirstRows(String count);

  /// No description provided for @importWizSensitiveField.
  ///
  /// In en, this message translates to:
  /// **'Sensitive field'**
  String get importWizSensitiveField;

  /// No description provided for @importWizDataValidationWarnings.
  ///
  /// In en, this message translates to:
  /// **'Data Validation Warnings'**
  String get importWizDataValidationWarnings;

  /// No description provided for @importWizValidationRowFormat.
  ///
  /// In en, this message translates to:
  /// **'Row {row}, Col {col}: {msg}'**
  String importWizValidationRowFormat(String row, String col, String msg);

  /// No description provided for @importWizImportSummary.
  ///
  /// In en, this message translates to:
  /// **'Import Configuration Summary'**
  String get importWizImportSummary;

  /// No description provided for @importWizSummaryTargetDatabase.
  ///
  /// In en, this message translates to:
  /// **'Target database'**
  String get importWizSummaryTargetDatabase;

  /// No description provided for @importWizSummaryTargetTable.
  ///
  /// In en, this message translates to:
  /// **'Target table'**
  String get importWizSummaryTargetTable;

  /// No description provided for @importWizSummaryFile.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get importWizSummaryFile;

  /// No description provided for @importWizSummaryMappedColumns.
  ///
  /// In en, this message translates to:
  /// **'Mapped columns'**
  String get importWizSummaryMappedColumns;

  /// No description provided for @importWizSummaryDataRows.
  ///
  /// In en, this message translates to:
  /// **'Data rows'**
  String get importWizSummaryDataRows;

  /// No description provided for @importWizConflictStrategy.
  ///
  /// In en, this message translates to:
  /// **'Conflict Resolution Strategy'**
  String get importWizConflictStrategy;

  /// No description provided for @importWizConflictSkip.
  ///
  /// In en, this message translates to:
  /// **'Skip duplicates'**
  String get importWizConflictSkip;

  /// No description provided for @importWizConflictSkipDesc.
  ///
  /// In en, this message translates to:
  /// **'When a duplicate key is encountered, skip the row and continue importing'**
  String get importWizConflictSkipDesc;

  /// No description provided for @importWizConflictUpdate.
  ///
  /// In en, this message translates to:
  /// **'Update existing rows'**
  String get importWizConflictUpdate;

  /// No description provided for @importWizConflictUpdateDesc.
  ///
  /// In en, this message translates to:
  /// **'When a duplicate key is encountered, update the existing data'**
  String get importWizConflictUpdateDesc;

  /// No description provided for @importWizConflictAbort.
  ///
  /// In en, this message translates to:
  /// **'Abort import'**
  String get importWizConflictAbort;

  /// No description provided for @importWizConflictAbortDesc.
  ///
  /// In en, this message translates to:
  /// **'When a duplicate key is encountered, stop the import immediately'**
  String get importWizConflictAbortDesc;

  /// No description provided for @importWizConflictSkipName.
  ///
  /// In en, this message translates to:
  /// **'Skip duplicates'**
  String get importWizConflictSkipName;

  /// No description provided for @importWizConflictUpdateName.
  ///
  /// In en, this message translates to:
  /// **'Update existing'**
  String get importWizConflictUpdateName;

  /// No description provided for @importWizConflictAbortName.
  ///
  /// In en, this message translates to:
  /// **'Abort'**
  String get importWizConflictAbortName;

  /// No description provided for @importWizImporting.
  ///
  /// In en, this message translates to:
  /// **'Importing...'**
  String get importWizImporting;

  /// No description provided for @importWizRowsProgress.
  ///
  /// In en, this message translates to:
  /// **'{imported}/{total} rows'**
  String importWizRowsProgress(String imported, String total);

  /// No description provided for @importWizFailedRows.
  ///
  /// In en, this message translates to:
  /// **'Failed: {count} rows'**
  String importWizFailedRows(String count);

  /// No description provided for @importWizImportComplete.
  ///
  /// In en, this message translates to:
  /// **'Import Complete!'**
  String get importWizImportComplete;

  /// No description provided for @importWizImportFailed.
  ///
  /// In en, this message translates to:
  /// **'Import failed: {error}'**
  String importWizImportFailed(String error);

  /// No description provided for @importWizImportSuccessMsg.
  ///
  /// In en, this message translates to:
  /// **'Successfully imported {count} rows'**
  String importWizImportSuccessMsg(String count);

  /// No description provided for @importWizImportErrorMsg.
  ///
  /// In en, this message translates to:
  /// **'An error occurred during import'**
  String get importWizImportErrorMsg;

  /// No description provided for @importWizPreviousStep.
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get importWizPreviousStep;

  /// No description provided for @importWizClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get importWizClose;

  /// No description provided for @importWizStartImport.
  ///
  /// In en, this message translates to:
  /// **'Start Import'**
  String get importWizStartImport;

  /// No description provided for @importWizNextStep.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get importWizNextStep;

  /// No description provided for @importWizReimport.
  ///
  /// In en, this message translates to:
  /// **'Re-import'**
  String get importWizReimport;

  /// No description provided for @importWizLoadDatabasesFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load database list: {error}'**
  String importWizLoadDatabasesFailed(String error);

  /// No description provided for @importWizLoadTablesFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load table list: {error}'**
  String importWizLoadTablesFailed(String error);

  /// No description provided for @importWizPickFileFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to select file: {error}'**
  String importWizPickFileFailed(String error);

  /// No description provided for @importWizAnalysisFailed.
  ///
  /// In en, this message translates to:
  /// **'Analysis failed: {error}'**
  String importWizAnalysisFailed(String error);

  /// No description provided for @importWizMappingFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to generate column mapping: {error}'**
  String importWizMappingFailed(String error);

  /// No description provided for @importWizFileAnalysisFailed.
  ///
  /// In en, this message translates to:
  /// **'File analysis failed'**
  String get importWizFileAnalysisFailed;

  /// No description provided for @importWizImportFailedGeneric.
  ///
  /// In en, this message translates to:
  /// **'Import failed'**
  String get importWizImportFailedGeneric;

  /// No description provided for @importWizNotSelected.
  ///
  /// In en, this message translates to:
  /// **'Not selected'**
  String get importWizNotSelected;

  /// No description provided for @importWizNotSet.
  ///
  /// In en, this message translates to:
  /// **'Not set'**
  String get importWizNotSet;

  /// No description provided for @importWizUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get importWizUnknown;

  /// No description provided for @importWizPiiDetectionSummary.
  ///
  /// In en, this message translates to:
  /// **'PII Detection'**
  String get importWizPiiDetectionSummary;

  /// No description provided for @importWizSensitiveFieldCount.
  ///
  /// In en, this message translates to:
  /// **'{count} sensitive fields'**
  String importWizSensitiveFieldCount(String count);

  /// No description provided for @smartImportAnalyzingDetail.
  ///
  /// In en, this message translates to:
  /// **'AI is identifying field types and generating CREATE TABLE statement'**
  String get smartImportAnalyzingDetail;

  /// No description provided for @smartImportColumnMapping.
  ///
  /// In en, this message translates to:
  /// **'Column Mapping'**
  String get smartImportColumnMapping;

  /// No description provided for @smartImportColumnsMapped.
  ///
  /// In en, this message translates to:
  /// **'{mapped}/{total} columns mapped'**
  String smartImportColumnsMapped(String mapped, String total);

  /// No description provided for @smartImportFileColumn.
  ///
  /// In en, this message translates to:
  /// **'File Column'**
  String get smartImportFileColumn;

  /// No description provided for @smartImportTableColumn.
  ///
  /// In en, this message translates to:
  /// **'Table Column'**
  String get smartImportTableColumn;

  /// No description provided for @smartImportConflictResolution.
  ///
  /// In en, this message translates to:
  /// **'Conflict Resolution'**
  String get smartImportConflictResolution;

  /// No description provided for @smartImportDataPreview.
  ///
  /// In en, this message translates to:
  /// **'Data Preview'**
  String get smartImportDataPreview;

  /// No description provided for @smartImportFirstRows.
  ///
  /// In en, this message translates to:
  /// **'First {count} rows'**
  String smartImportFirstRows(String count);

  /// No description provided for @smartImportBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get smartImportBack;

  /// No description provided for @smartImportBackgroundTask.
  ///
  /// In en, this message translates to:
  /// **'Background Import'**
  String get smartImportBackgroundTask;

  /// No description provided for @smartImportFailedToGenerateSql.
  ///
  /// In en, this message translates to:
  /// **'-- Failed to generate CREATE TABLE statement'**
  String get smartImportFailedToGenerateSql;

  /// No description provided for @smartImportTargetTableSelected.
  ///
  /// In en, this message translates to:
  /// **'Target table selected: {table}'**
  String smartImportTargetTableSelected(String table);

  /// No description provided for @smartImportTargetTableEntered.
  ///
  /// In en, this message translates to:
  /// **'Target table entered: {table}'**
  String smartImportTargetTableEntered(String table);

  /// No description provided for @smartImportAnalysisFailed.
  ///
  /// In en, this message translates to:
  /// **'File analysis failed: {error}'**
  String smartImportAnalysisFailed(String error);

  /// No description provided for @smartImportColumnMappingsComplete.
  ///
  /// In en, this message translates to:
  /// **'Column mapping complete: {mapped}/{total} columns auto-matched'**
  String smartImportColumnMappingsComplete(String mapped, String total);

  /// No description provided for @smartImportPiiDetected.
  ///
  /// In en, this message translates to:
  /// **'PII Detection: Sensitive fields found - {types}'**
  String smartImportPiiDetected(String types);

  /// No description provided for @smartImportPiiNone.
  ///
  /// In en, this message translates to:
  /// **'PII Detection: No sensitive fields found'**
  String get smartImportPiiNone;

  /// No description provided for @smartImportPiiFailed.
  ///
  /// In en, this message translates to:
  /// **'PII Detection failed: {error}'**
  String smartImportPiiFailed(String error);

  /// No description provided for @smartImportPreviewGenerated.
  ///
  /// In en, this message translates to:
  /// **'Data preview generated ({count} rows)'**
  String smartImportPreviewGenerated(String count);

  /// No description provided for @smartImportPreviewFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to generate preview: {error}'**
  String smartImportPreviewFailed(String error);

  /// No description provided for @smartImportMappingFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to generate column mapping: {error}'**
  String smartImportMappingFailed(String error);

  /// No description provided for @importServiceStartImport.
  ///
  /// In en, this message translates to:
  /// **'Starting data import to table \"{table}\"...'**
  String importServiceStartImport(String table);

  /// No description provided for @importServiceColumnMapping.
  ///
  /// In en, this message translates to:
  /// **'Column mapping: {mapped}/{total} columns mapped'**
  String importServiceColumnMapping(String mapped, String total);

  /// No description provided for @importServiceConflictStrategy.
  ///
  /// In en, this message translates to:
  /// **'Conflict resolution strategy: {strategy}'**
  String importServiceConflictStrategy(String strategy);

  /// No description provided for @importServiceImporting.
  ///
  /// In en, this message translates to:
  /// **'Starting data import...'**
  String get importServiceImporting;

  /// No description provided for @importServiceBatchSuccess.
  ///
  /// In en, this message translates to:
  /// **'Batch {batch}: Successfully imported {count} rows'**
  String importServiceBatchSuccess(String batch, String count);

  /// No description provided for @importServiceBatchInsertFailed.
  ///
  /// In en, this message translates to:
  /// **'Batch insert failed ({count} rows), trying row-by-row...'**
  String importServiceBatchInsertFailed(String count);

  /// No description provided for @importServiceUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Update failed: {error}'**
  String importServiceUpdateFailed(String error);

  /// No description provided for @importServiceDataTooLong.
  ///
  /// In en, this message translates to:
  /// **'Row {row} data too long, skipped'**
  String importServiceDataTooLong(String row);

  /// No description provided for @importServiceRowInsertFailed.
  ///
  /// In en, this message translates to:
  /// **'Row {row} insert failed: {error}'**
  String importServiceRowInsertFailed(String row, String error);

  /// No description provided for @importServiceBatchSkipped.
  ///
  /// In en, this message translates to:
  /// **'Batch skipped: {count} rows (duplicates)'**
  String importServiceBatchSkipped(String count);

  /// No description provided for @importServiceBatchUpdated.
  ///
  /// In en, this message translates to:
  /// **'Batch updated: {count} rows'**
  String importServiceBatchUpdated(String count);

  /// No description provided for @importServiceBatchFailed.
  ///
  /// In en, this message translates to:
  /// **'Batch failed: {count} rows'**
  String importServiceBatchFailed(String count);

  /// No description provided for @importServicePhaseProgress.
  ///
  /// In en, this message translates to:
  /// **'Imported {imported} rows, skipped {skipped} rows, updated {updated} rows...'**
  String importServicePhaseProgress(
    String imported,
    String skipped,
    String updated,
  );

  /// No description provided for @importServiceImportCancelled.
  ///
  /// In en, this message translates to:
  /// **'Import cancelled'**
  String get importServiceImportCancelled;

  /// No description provided for @importServiceFileReadFailed.
  ///
  /// In en, this message translates to:
  /// **'File read failed: {error}'**
  String importServiceFileReadFailed(String error);

  /// No description provided for @importServiceImportComplete.
  ///
  /// In en, this message translates to:
  /// **'Import complete! Success: {imported} rows, Failed: {failed} rows'**
  String importServiceImportComplete(String imported, String failed);

  /// No description provided for @taskExecutorAnalyzeFile.
  ///
  /// In en, this message translates to:
  /// **'Analyzing file: {path}'**
  String taskExecutorAnalyzeFile(String path);

  /// No description provided for @taskExecutorFileFormat.
  ///
  /// In en, this message translates to:
  /// **'File format: {format}, Encoding: {encoding}, Estimated rows: {rows}'**
  String taskExecutorFileFormat(String format, String encoding, String rows);

  /// No description provided for @taskExecutorTableNotExists.
  ///
  /// In en, this message translates to:
  /// **'Table does not exist, creating...'**
  String get taskExecutorTableNotExists;

  /// No description provided for @taskExecutorTableCreated.
  ///
  /// In en, this message translates to:
  /// **'Table created successfully'**
  String get taskExecutorTableCreated;

  /// No description provided for @taskExecutorTableCreateFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to create table'**
  String get taskExecutorTableCreateFailed;

  /// No description provided for @taskExecutorTableNotExistsError.
  ///
  /// In en, this message translates to:
  /// **'Target table \"{table}\" does not exist. Please create the table first.'**
  String taskExecutorTableNotExistsError(String table);

  /// No description provided for @taskExecutorNoColumnMapping.
  ///
  /// In en, this message translates to:
  /// **'No usable column mapping. Please check that file fields match table fields.'**
  String get taskExecutorNoColumnMapping;

  /// No description provided for @taskExecutorColumnMapping.
  ///
  /// In en, this message translates to:
  /// **'Column mapping: {mapped}/{total} columns mapped'**
  String taskExecutorColumnMapping(String mapped, String total);

  /// No description provided for @taskExecutorStartImport.
  ///
  /// In en, this message translates to:
  /// **'Starting data import...'**
  String get taskExecutorStartImport;

  /// No description provided for @taskExecutorImportComplete.
  ///
  /// In en, this message translates to:
  /// **'Import complete! Success: {imported} rows, Failed: {failed} rows'**
  String taskExecutorImportComplete(String imported, String failed);

  /// No description provided for @taskExecutorImportFinished.
  ///
  /// In en, this message translates to:
  /// **'Import complete'**
  String get taskExecutorImportFinished;

  /// No description provided for @serverConnectNoServerLearnMore.
  ///
  /// In en, this message translates to:
  /// **'Don\'t have a server? Learn more'**
  String get serverConnectNoServerLearnMore;

  /// No description provided for @touchpointLiteLearnMore.
  ///
  /// In en, this message translates to:
  /// **'See how'**
  String get touchpointLiteLearnMore;

  /// No description provided for @touchpointLiteSlowQueryTitle.
  ///
  /// In en, this message translates to:
  /// **'Recurring slow queries?'**
  String get touchpointLiteSlowQueryTitle;

  /// No description provided for @touchpointLiteSlowQueryDesc.
  ///
  /// In en, this message translates to:
  /// **'DbMaster Server can track these automatically and alert you on schedule.'**
  String get touchpointLiteSlowQueryDesc;

  /// No description provided for @touchpointLiteSchemaDiffTitle.
  ///
  /// In en, this message translates to:
  /// **'Repeat schema comparisons?'**
  String get touchpointLiteSchemaDiffTitle;

  /// No description provided for @touchpointLiteSchemaDiffDesc.
  ///
  /// In en, this message translates to:
  /// **'DbMaster Server can run this on a schedule, retry on failure, and send Feishu/DingTalk alerts.'**
  String get touchpointLiteSchemaDiffDesc;

  /// No description provided for @touchpointLiteDataSyncTitle.
  ///
  /// In en, this message translates to:
  /// **'Tired of running this manually?'**
  String get touchpointLiteDataSyncTitle;

  /// No description provided for @touchpointLiteDataSyncDesc.
  ///
  /// In en, this message translates to:
  /// **'DbMaster Server can automate this sync with retries and team notifications.'**
  String get touchpointLiteDataSyncDesc;

  /// No description provided for @driftMenuLabel.
  ///
  /// In en, this message translates to:
  /// **'Schema Drift Alerts'**
  String get driftMenuLabel;

  /// No description provided for @driftTaskListTitle.
  ///
  /// In en, this message translates to:
  /// **'Schema Drift Alerts'**
  String get driftTaskListTitle;

  /// No description provided for @driftTaskListEmpty.
  ///
  /// In en, this message translates to:
  /// **'No drift tasks yet. Create one to monitor a source database for schema changes.'**
  String get driftTaskListEmpty;

  /// No description provided for @driftTaskListEmptyHint.
  ///
  /// In en, this message translates to:
  /// **'Drift tasks snapshot a read-only source database on a schedule and alert you when the schema changes.'**
  String get driftTaskListEmptyHint;

  /// No description provided for @driftCreateTaskButton.
  ///
  /// In en, this message translates to:
  /// **'New Drift Task'**
  String get driftCreateTaskButton;

  /// No description provided for @driftRunNowButton.
  ///
  /// In en, this message translates to:
  /// **'Run Now'**
  String get driftRunNowButton;

  /// No description provided for @driftHistoryButton.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get driftHistoryButton;

  /// No description provided for @driftViewDiffButton.
  ///
  /// In en, this message translates to:
  /// **'View Diff'**
  String get driftViewDiffButton;

  /// No description provided for @driftDeleteTaskButton.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get driftDeleteTaskButton;

  /// No description provided for @driftColTaskName.
  ///
  /// In en, this message translates to:
  /// **'Task'**
  String get driftColTaskName;

  /// No description provided for @driftColSource.
  ///
  /// In en, this message translates to:
  /// **'Source database'**
  String get driftColSource;

  /// No description provided for @driftColInterval.
  ///
  /// In en, this message translates to:
  /// **'Interval'**
  String get driftColInterval;

  /// No description provided for @driftColLastRun.
  ///
  /// In en, this message translates to:
  /// **'Last run'**
  String get driftColLastRun;

  /// No description provided for @driftColStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get driftColStatus;

  /// No description provided for @driftIntervalMinutes.
  ///
  /// In en, this message translates to:
  /// **'Every {minutes} min'**
  String driftIntervalMinutes(String minutes);

  /// No description provided for @driftIntervalHours.
  ///
  /// In en, this message translates to:
  /// **'Every {hours} h'**
  String driftIntervalHours(String hours);

  /// No description provided for @driftIntervalUnknown.
  ///
  /// In en, this message translates to:
  /// **'Server default'**
  String get driftIntervalUnknown;

  /// No description provided for @driftEditIntervalTooltip.
  ///
  /// In en, this message translates to:
  /// **'Edit check interval'**
  String get driftEditIntervalTooltip;

  /// No description provided for @driftEditIntervalTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Check Interval'**
  String get driftEditIntervalTitle;

  /// No description provided for @driftIntervalUpdated.
  ///
  /// In en, this message translates to:
  /// **'Interval updated. It applies from the next scheduled scan.'**
  String get driftIntervalUpdated;

  /// No description provided for @driftStatusNever.
  ///
  /// In en, this message translates to:
  /// **'Never run'**
  String get driftStatusNever;

  /// No description provided for @driftStatusRunning.
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get driftStatusRunning;

  /// No description provided for @driftStatusSucceeded.
  ///
  /// In en, this message translates to:
  /// **'Succeeded'**
  String get driftStatusSucceeded;

  /// No description provided for @driftStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get driftStatusFailed;

  /// No description provided for @driftStatusUnknown.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get driftStatusUnknown;

  /// No description provided for @driftCreateTaskTitle.
  ///
  /// In en, this message translates to:
  /// **'Create Drift Task'**
  String get driftCreateTaskTitle;

  /// No description provided for @driftCreateTaskName.
  ///
  /// In en, this message translates to:
  /// **'Task name'**
  String get driftCreateTaskName;

  /// No description provided for @driftCreateTaskSource.
  ///
  /// In en, this message translates to:
  /// **'Source connection (read-only)'**
  String get driftCreateTaskSource;

  /// No description provided for @driftCreateTaskNoSources.
  ///
  /// In en, this message translates to:
  /// **'No read-only source connections yet.'**
  String get driftCreateTaskNoSources;

  /// No description provided for @driftCreateTaskAddSource.
  ///
  /// In en, this message translates to:
  /// **'Add a source connection'**
  String get driftCreateTaskAddSource;

  /// No description provided for @driftCreateTaskInterval.
  ///
  /// In en, this message translates to:
  /// **'Check interval'**
  String get driftCreateTaskInterval;

  /// No description provided for @driftCreateTaskWebhook.
  ///
  /// In en, this message translates to:
  /// **'Webhook URL (optional, https)'**
  String get driftCreateTaskWebhook;

  /// No description provided for @driftCreateTaskWebhookHint.
  ///
  /// In en, this message translates to:
  /// **'Feishu / DingTalk / Slack webhook — comma-separated for multiple'**
  String get driftCreateTaskWebhookHint;

  /// No description provided for @driftCreateTaskSubmit.
  ///
  /// In en, this message translates to:
  /// **'Create Task'**
  String get driftCreateTaskSubmit;

  /// No description provided for @driftCreateTaskInvalidName.
  ///
  /// In en, this message translates to:
  /// **'Enter a task name.'**
  String get driftCreateTaskInvalidName;

  /// No description provided for @driftCreateTaskInvalidSource.
  ///
  /// In en, this message translates to:
  /// **'Select a source connection.'**
  String get driftCreateTaskInvalidSource;

  /// No description provided for @driftCreateTaskInvalidInterval.
  ///
  /// In en, this message translates to:
  /// **'Interval must be between 1 and 1440 minutes.'**
  String get driftCreateTaskInvalidInterval;

  /// No description provided for @driftCreateTaskInvalidWebhook.
  ///
  /// In en, this message translates to:
  /// **'Webhook URL must start with https://'**
  String get driftCreateTaskInvalidWebhook;

  /// No description provided for @driftGatedTitle.
  ///
  /// In en, this message translates to:
  /// **'Server license gated'**
  String get driftGatedTitle;

  /// No description provided for @driftGatedBody.
  ///
  /// In en, this message translates to:
  /// **'Activate or renew the Server license to create or run drift tasks. Existing data is still visible.'**
  String get driftGatedBody;

  /// No description provided for @driftCreateSourceTitle.
  ///
  /// In en, this message translates to:
  /// **'Add Read-Only Source Connection'**
  String get driftCreateSourceTitle;

  /// No description provided for @driftCreateSourceDbType.
  ///
  /// In en, this message translates to:
  /// **'Database type'**
  String get driftCreateSourceDbType;

  /// No description provided for @driftCreateSourceHost.
  ///
  /// In en, this message translates to:
  /// **'Host'**
  String get driftCreateSourceHost;

  /// No description provided for @driftCreateSourcePort.
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get driftCreateSourcePort;

  /// No description provided for @driftCreateSourceUsername.
  ///
  /// In en, this message translates to:
  /// **'Username (read-only account)'**
  String get driftCreateSourceUsername;

  /// No description provided for @driftCreateSourcePassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get driftCreateSourcePassword;

  /// No description provided for @driftCreateSourceDatabase.
  ///
  /// In en, this message translates to:
  /// **'Database (optional)'**
  String get driftCreateSourceDatabase;

  /// No description provided for @driftCreateSourceSubmit.
  ///
  /// In en, this message translates to:
  /// **'Add Connection'**
  String get driftCreateSourceSubmit;

  /// No description provided for @driftCreateSourceCanaryNote.
  ///
  /// In en, this message translates to:
  /// **'The Server probes the account before saving — writable accounts are rejected. Use a SELECT-only account.'**
  String get driftCreateSourceCanaryNote;

  /// No description provided for @driftRunQueued.
  ///
  /// In en, this message translates to:
  /// **'Run queued. The list updates automatically when the run completes.'**
  String get driftRunQueued;

  /// No description provided for @driftRunFailed.
  ///
  /// In en, this message translates to:
  /// **'Run failed: {error}'**
  String driftRunFailed(String error);

  /// No description provided for @driftHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Run History'**
  String get driftHistoryTitle;

  /// No description provided for @driftHistoryColStarted.
  ///
  /// In en, this message translates to:
  /// **'Started'**
  String get driftHistoryColStarted;

  /// No description provided for @driftHistoryColDuration.
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get driftHistoryColDuration;

  /// No description provided for @driftHistoryColDrift.
  ///
  /// In en, this message translates to:
  /// **'Drift'**
  String get driftHistoryColDrift;

  /// No description provided for @driftHistoryColTrigger.
  ///
  /// In en, this message translates to:
  /// **'Trigger'**
  String get driftHistoryColTrigger;

  /// No description provided for @driftHistoryColWebhook.
  ///
  /// In en, this message translates to:
  /// **'Webhook'**
  String get driftHistoryColWebhook;

  /// No description provided for @driftHistoryNoDrift.
  ///
  /// In en, this message translates to:
  /// **'No drift'**
  String get driftHistoryNoDrift;

  /// No description provided for @driftHistoryHasDrift.
  ///
  /// In en, this message translates to:
  /// **'{count} change(s)'**
  String driftHistoryHasDrift(String count);

  /// No description provided for @driftHistoryError.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String driftHistoryError(String error);

  /// No description provided for @driftTriggerManual.
  ///
  /// In en, this message translates to:
  /// **'Manual'**
  String get driftTriggerManual;

  /// No description provided for @driftTriggerScheduler.
  ///
  /// In en, this message translates to:
  /// **'Scheduler'**
  String get driftTriggerScheduler;

  /// No description provided for @driftDiffTitle.
  ///
  /// In en, this message translates to:
  /// **'Drift Diff'**
  String get driftDiffTitle;

  /// No description provided for @driftDiffPickSnapshots.
  ///
  /// In en, this message translates to:
  /// **'Pick two snapshots to compare'**
  String get driftDiffPickSnapshots;

  /// No description provided for @driftDiffSnapshotNewer.
  ///
  /// In en, this message translates to:
  /// **'Newer'**
  String get driftDiffSnapshotNewer;

  /// No description provided for @driftDiffSnapshotOlder.
  ///
  /// In en, this message translates to:
  /// **'Older'**
  String get driftDiffSnapshotOlder;

  /// No description provided for @driftDiffCompare.
  ///
  /// In en, this message translates to:
  /// **'Compare'**
  String get driftDiffCompare;

  /// No description provided for @driftDiffNoComparable.
  ///
  /// In en, this message translates to:
  /// **'Pick two different snapshots to compare.'**
  String get driftDiffNoComparable;

  /// No description provided for @driftDiffEmpty.
  ///
  /// In en, this message translates to:
  /// **'No changes between these two snapshots.'**
  String get driftDiffEmpty;

  /// No description provided for @driftLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get driftLoading;

  /// No description provided for @driftRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get driftRetry;

  /// No description provided for @driftClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get driftClose;

  /// No description provided for @viewModeTable.
  ///
  /// In en, this message translates to:
  /// **'Table'**
  String get viewModeTable;

  /// No description provided for @viewModeChart.
  ///
  /// In en, this message translates to:
  /// **'Chart'**
  String get viewModeChart;

  /// No description provided for @viewModeCard.
  ///
  /// In en, this message translates to:
  /// **'Card'**
  String get viewModeCard;

  /// No description provided for @viewModeDocument.
  ///
  /// In en, this message translates to:
  /// **'Documents'**
  String get viewModeDocument;

  /// No description provided for @viewModeJsonTree.
  ///
  /// In en, this message translates to:
  /// **'JSON Tree'**
  String get viewModeJsonTree;

  /// No description provided for @viewModeKeyValue.
  ///
  /// In en, this message translates to:
  /// **'Key-Value'**
  String get viewModeKeyValue;

  /// No description provided for @documentExpand.
  ///
  /// In en, this message translates to:
  /// **'Expand'**
  String get documentExpand;

  /// No description provided for @documentCollapse.
  ///
  /// In en, this message translates to:
  /// **'Collapse'**
  String get documentCollapse;

  /// No description provided for @documentExpandMore.
  ///
  /// In en, this message translates to:
  /// **'Expand {count} more fields'**
  String documentExpandMore(int count);

  /// No description provided for @jsonTreeItemCount.
  ///
  /// In en, this message translates to:
  /// **'{count} items'**
  String jsonTreeItemCount(int count);

  /// No description provided for @keyValueField.
  ///
  /// In en, this message translates to:
  /// **'Field'**
  String get keyValueField;

  /// No description provided for @keyValueValue.
  ///
  /// In en, this message translates to:
  /// **'Value'**
  String get keyValueValue;

  /// No description provided for @keyValueFieldLabel.
  ///
  /// In en, this message translates to:
  /// **'Field: {field}'**
  String keyValueFieldLabel(String field);

  /// No description provided for @keyValueLengthLabel.
  ///
  /// In en, this message translates to:
  /// **'Length: {length} chars'**
  String keyValueLengthLabel(int length);

  /// No description provided for @chartViewComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Chart view (coming soon)'**
  String get chartViewComingSoon;

  /// No description provided for @chartExportSuccess.
  ///
  /// In en, this message translates to:
  /// **'Chart saved to {path}'**
  String chartExportSuccess(String path);

  /// No description provided for @chartExportFailed.
  ///
  /// In en, this message translates to:
  /// **'Chart export failed: {error}'**
  String chartExportFailed(String error);

  /// No description provided for @chartSamplingNotice.
  ///
  /// In en, this message translates to:
  /// **'Large dataset: sampled {count} points for performance'**
  String chartSamplingNotice(int count);

  /// No description provided for @chartAiTrend.
  ///
  /// In en, this message translates to:
  /// **'AI Trend Analysis'**
  String get chartAiTrend;

  /// No description provided for @chartTypeLine.
  ///
  /// In en, this message translates to:
  /// **'Line'**
  String get chartTypeLine;

  /// No description provided for @chartTypeBar.
  ///
  /// In en, this message translates to:
  /// **'Bar'**
  String get chartTypeBar;

  /// No description provided for @chartTypePie.
  ///
  /// In en, this message translates to:
  /// **'Pie'**
  String get chartTypePie;

  /// No description provided for @chartTypeScatter.
  ///
  /// In en, this message translates to:
  /// **'Scatter'**
  String get chartTypeScatter;

  /// No description provided for @statisticsPanelTitle.
  ///
  /// In en, this message translates to:
  /// **'Statistics'**
  String get statisticsPanelTitle;

  /// No description provided for @exportStepBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get exportStepBack;

  /// No description provided for @exportStepNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get exportStepNext;

  /// No description provided for @noJsonDataToSample.
  ///
  /// In en, this message translates to:
  /// **'No data to sample'**
  String get noJsonDataToSample;

  /// No description provided for @noLeafNodes.
  ///
  /// In en, this message translates to:
  /// **'No extractable fields'**
  String get noLeafNodes;

  /// No description provided for @fieldNotInAllRows.
  ///
  /// In en, this message translates to:
  /// **'not in all rows'**
  String get fieldNotInAllRows;

  /// No description provided for @commonRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry;

  /// No description provided for @extensionNoAdapter.
  ///
  /// In en, this message translates to:
  /// **'No adapter'**
  String get extensionNoAdapter;

  /// No description provided for @extensionNotPostgres.
  ///
  /// In en, this message translates to:
  /// **'Not a PostgreSQL connection'**
  String get extensionNotPostgres;

  /// No description provided for @extensionLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load members'**
  String get extensionLoadFailed;

  /// No description provided for @extensionTypes.
  ///
  /// In en, this message translates to:
  /// **'Types'**
  String get extensionTypes;

  /// No description provided for @extensionFunctions.
  ///
  /// In en, this message translates to:
  /// **'Functions'**
  String get extensionFunctions;

  /// No description provided for @extensionOperators.
  ///
  /// In en, this message translates to:
  /// **'Operators'**
  String get extensionOperators;

  /// No description provided for @extensionSchema.
  ///
  /// In en, this message translates to:
  /// **'Schema'**
  String get extensionSchema;

  /// No description provided for @extensionDescription.
  ///
  /// In en, this message translates to:
  /// **'Description'**
  String get extensionDescription;

  /// No description provided for @vectorLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load vector indexes'**
  String get vectorLoadFailed;

  /// No description provided for @vectorNoAdapter.
  ///
  /// In en, this message translates to:
  /// **'No adapter'**
  String get vectorNoAdapter;

  /// No description provided for @vectorNoIndexes.
  ///
  /// In en, this message translates to:
  /// **'No vector indexes defined'**
  String get vectorNoIndexes;

  /// No description provided for @jsonInvalidJson.
  ///
  /// In en, this message translates to:
  /// **'Invalid JSON'**
  String get jsonInvalidJson;

  /// No description provided for @jsonNoMatches.
  ///
  /// In en, this message translates to:
  /// **'No matches'**
  String get jsonNoMatches;

  /// No description provided for @jsonSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search keys or values...'**
  String get jsonSearchHint;

  /// No description provided for @jsonMaxDepthReached.
  ///
  /// In en, this message translates to:
  /// **'<max depth reached>'**
  String get jsonMaxDepthReached;

  /// No description provided for @jsonTruncated.
  ///
  /// In en, this message translates to:
  /// **'<truncated>'**
  String get jsonTruncated;

  /// No description provided for @commonApply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get commonApply;

  /// No description provided for @pragmaExplorerTitle.
  ///
  /// In en, this message translates to:
  /// **'PRAGMA Explorer'**
  String get pragmaExplorerTitle;

  /// No description provided for @pragmaNoAdapter.
  ///
  /// In en, this message translates to:
  /// **'No adapter'**
  String get pragmaNoAdapter;

  /// No description provided for @pragmaNotSQLite.
  ///
  /// In en, this message translates to:
  /// **'PRAGMA Explorer is only available for SQLite connections'**
  String get pragmaNotSQLite;

  /// No description provided for @pragmaSearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search PRAGMA by name or value...'**
  String get pragmaSearchHint;

  /// No description provided for @pragmaCategoryPerformance.
  ///
  /// In en, this message translates to:
  /// **'Performance'**
  String get pragmaCategoryPerformance;

  /// No description provided for @pragmaCategoryDurability.
  ///
  /// In en, this message translates to:
  /// **'Durability'**
  String get pragmaCategoryDurability;

  /// No description provided for @pragmaCategorySecurity.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get pragmaCategorySecurity;

  /// No description provided for @pragmaCategoryDebug.
  ///
  /// In en, this message translates to:
  /// **'Debug'**
  String get pragmaCategoryDebug;

  /// No description provided for @pragmaSetValue.
  ///
  /// In en, this message translates to:
  /// **'Set value'**
  String get pragmaSetValue;

  /// No description provided for @sqliteCopyFilePath.
  ///
  /// In en, this message translates to:
  /// **'Copy File Path'**
  String get sqliteCopyFilePath;

  /// No description provided for @sqliteOpenInFolder.
  ///
  /// In en, this message translates to:
  /// **'Open in Folder'**
  String get sqliteOpenInFolder;

  /// No description provided for @sqliteToggleWalMode.
  ///
  /// In en, this message translates to:
  /// **'Toggle WAL Mode'**
  String get sqliteToggleWalMode;

  /// No description provided for @sqliteOptimizeDatabase.
  ///
  /// In en, this message translates to:
  /// **'Optimize Database'**
  String get sqliteOptimizeDatabase;

  /// No description provided for @sqliteVacuum.
  ///
  /// In en, this message translates to:
  /// **'VACUUM'**
  String get sqliteVacuum;

  /// No description provided for @sqliteIntegrityCheck.
  ///
  /// In en, this message translates to:
  /// **'Integrity Check'**
  String get sqliteIntegrityCheck;

  /// No description provided for @sqliteSaveAs.
  ///
  /// In en, this message translates to:
  /// **'Save As…'**
  String get sqliteSaveAs;

  /// No description provided for @sqliteStatusWal.
  ///
  /// In en, this message translates to:
  /// **'WAL'**
  String get sqliteStatusWal;

  /// No description provided for @sqliteStatusPageSize.
  ///
  /// In en, this message translates to:
  /// **'Page'**
  String get sqliteStatusPageSize;

  /// No description provided for @sqliteStatusFileSize.
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get sqliteStatusFileSize;

  /// No description provided for @sqliteAttachDatabase.
  ///
  /// In en, this message translates to:
  /// **'Attach Database…'**
  String get sqliteAttachDatabase;

  /// No description provided for @sqliteDetach.
  ///
  /// In en, this message translates to:
  /// **'Detach'**
  String get sqliteDetach;

  /// No description provided for @sqliteAttachFileLabel.
  ///
  /// In en, this message translates to:
  /// **'Database file'**
  String get sqliteAttachFileLabel;

  /// No description provided for @sqliteAttachFileHint.
  ///
  /// In en, this message translates to:
  /// **'Pick a .db file to attach'**
  String get sqliteAttachFileHint;

  /// No description provided for @sqliteAttachPickFile.
  ///
  /// In en, this message translates to:
  /// **'Pick file'**
  String get sqliteAttachPickFile;

  /// No description provided for @sqliteAttachAliasLabel.
  ///
  /// In en, this message translates to:
  /// **'Alias'**
  String get sqliteAttachAliasLabel;

  /// No description provided for @sqliteAttachAliasHint.
  ///
  /// In en, this message translates to:
  /// **'archive'**
  String get sqliteAttachAliasHint;

  /// No description provided for @sqliteAttachAliasHelp.
  ///
  /// In en, this message translates to:
  /// **'Letters, digits, underscore. Used as the schema prefix in cross-database queries (e.g. SELECT * FROM alias.table).'**
  String get sqliteAttachAliasHelp;

  /// No description provided for @sqliteAttachButton.
  ///
  /// In en, this message translates to:
  /// **'Attach'**
  String get sqliteAttachButton;

  /// No description provided for @sqliteAttachSuccess.
  ///
  /// In en, this message translates to:
  /// **'Attached {alias}'**
  String sqliteAttachSuccess(String alias);

  /// No description provided for @sqliteAttachFailed.
  ///
  /// In en, this message translates to:
  /// **'Attach failed: {error}'**
  String sqliteAttachFailed(String error);

  /// No description provided for @sqliteDetachSuccess.
  ///
  /// In en, this message translates to:
  /// **'Detached {alias}'**
  String sqliteDetachSuccess(String alias);

  /// No description provided for @sqliteDetachFailed.
  ///
  /// In en, this message translates to:
  /// **'Detach failed: {error}'**
  String sqliteDetachFailed(String error);

  /// No description provided for @sqliteAttachAliasInvalid.
  ///
  /// In en, this message translates to:
  /// **'Alias must start with a letter or underscore and contain only letters, digits, underscores.'**
  String get sqliteAttachAliasInvalid;

  /// No description provided for @sqliteAttachAliasReserved.
  ///
  /// In en, this message translates to:
  /// **'Alias \"main\" and \"temp\" are reserved.'**
  String get sqliteAttachAliasReserved;

  /// No description provided for @sqliteAttachAliasKeyword.
  ///
  /// In en, this message translates to:
  /// **'Alias is a SQLite keyword. Pick a different name.'**
  String get sqliteAttachAliasKeyword;

  /// No description provided for @sqliteAttachAliasDuplicate.
  ///
  /// In en, this message translates to:
  /// **'An attached database with this alias already exists.'**
  String get sqliteAttachAliasDuplicate;

  /// No description provided for @mongoNestedFields.
  ///
  /// In en, this message translates to:
  /// **'Nested fields'**
  String get mongoNestedFields;

  /// No description provided for @healthMenuLabel.
  ///
  /// In en, this message translates to:
  /// **'Health Check'**
  String get healthMenuLabel;

  /// No description provided for @healthDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Health Check'**
  String get healthDialogTitle;

  /// No description provided for @healthDialogSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Scheduled database health monitoring (ADR-0004)'**
  String get healthDialogSubtitle;

  /// No description provided for @healthStatusHealthy.
  ///
  /// In en, this message translates to:
  /// **'Healthy'**
  String get healthStatusHealthy;

  /// No description provided for @healthStatusWarning.
  ///
  /// In en, this message translates to:
  /// **'Alerts active'**
  String get healthStatusWarning;

  /// No description provided for @healthStatusCritical.
  ///
  /// In en, this message translates to:
  /// **'Check failing'**
  String get healthStatusCritical;

  /// No description provided for @healthStatusUnknown.
  ///
  /// In en, this message translates to:
  /// **'No data'**
  String get healthStatusUnknown;

  /// No description provided for @healthNoTasks.
  ///
  /// In en, this message translates to:
  /// **'No health check tasks configured.'**
  String get healthNoTasks;

  /// No description provided for @healthNoTasksHint.
  ///
  /// In en, this message translates to:
  /// **'Tasks are created via the Server API or admin UI.'**
  String get healthNoTasksHint;

  /// No description provided for @healthBadgeAlerts.
  ///
  /// In en, this message translates to:
  /// **'{n} alerts'**
  String healthBadgeAlerts(int n);

  /// No description provided for @healthColumnTask.
  ///
  /// In en, this message translates to:
  /// **'Task'**
  String get healthColumnTask;

  /// No description provided for @healthColumnStatus.
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get healthColumnStatus;

  /// No description provided for @healthColumnLastCheck.
  ///
  /// In en, this message translates to:
  /// **'Last check'**
  String get healthColumnLastCheck;

  /// No description provided for @healthColumnConnection.
  ///
  /// In en, this message translates to:
  /// **'Connection'**
  String get healthColumnConnection;

  /// No description provided for @healthRunNow.
  ///
  /// In en, this message translates to:
  /// **'Run now'**
  String get healthRunNow;

  /// No description provided for @healthRunQueued.
  ///
  /// In en, this message translates to:
  /// **'Run queued — refreshing in a moment.'**
  String get healthRunQueued;

  /// No description provided for @healthRefreshFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load health results.'**
  String get healthRefreshFailed;

  /// No description provided for @healthNoResults.
  ///
  /// In en, this message translates to:
  /// **'No results yet'**
  String get healthNoResults;

  /// No description provided for @healthAgoJustNow.
  ///
  /// In en, this message translates to:
  /// **'just now'**
  String get healthAgoJustNow;

  /// No description provided for @healthAgoMinutes.
  ///
  /// In en, this message translates to:
  /// **'{n} min ago'**
  String healthAgoMinutes(int n);

  /// No description provided for @healthAgoHours.
  ///
  /// In en, this message translates to:
  /// **'{n} h ago'**
  String healthAgoHours(int n);

  /// No description provided for @healthAgoDays.
  ///
  /// In en, this message translates to:
  /// **'{n} d ago'**
  String healthAgoDays(int n);

  /// No description provided for @healthLatencyMs.
  ///
  /// In en, this message translates to:
  /// **'{ms} ms'**
  String healthLatencyMs(int ms);

  /// No description provided for @healthAlertsCount.
  ///
  /// In en, this message translates to:
  /// **'{n} alerts'**
  String healthAlertsCount(int n);

  /// No description provided for @healthMetricConnectivity.
  ///
  /// In en, this message translates to:
  /// **'Connectivity'**
  String get healthMetricConnectivity;

  /// No description provided for @healthMetricRowCount.
  ///
  /// In en, this message translates to:
  /// **'Row count'**
  String get healthMetricRowCount;

  /// No description provided for @healthMetricMissingPk.
  ///
  /// In en, this message translates to:
  /// **'Missing primary keys'**
  String get healthMetricMissingPk;

  /// No description provided for @healthMetricConnectionCount.
  ///
  /// In en, this message translates to:
  /// **'Connections'**
  String get healthMetricConnectionCount;

  /// No description provided for @healthClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get healthClose;

  /// No description provided for @healthLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get healthLoading;

  /// No description provided for @healthResultSuccess.
  ///
  /// In en, this message translates to:
  /// **'Success'**
  String get healthResultSuccess;

  /// No description provided for @healthResultPartial.
  ///
  /// In en, this message translates to:
  /// **'Partial'**
  String get healthResultPartial;

  /// No description provided for @healthResultFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get healthResultFailed;

  /// No description provided for @healthRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get healthRefresh;

  /// No description provided for @healthCreateTaskTitle.
  ///
  /// In en, this message translates to:
  /// **'Create Health Check Task'**
  String get healthCreateTaskTitle;

  /// No description provided for @healthCreateTaskName.
  ///
  /// In en, this message translates to:
  /// **'Task name'**
  String get healthCreateTaskName;

  /// No description provided for @healthCreateTaskInvalidName.
  ///
  /// In en, this message translates to:
  /// **'Please enter a task name.'**
  String get healthCreateTaskInvalidName;

  /// No description provided for @healthCreateTaskSource.
  ///
  /// In en, this message translates to:
  /// **'Source connection'**
  String get healthCreateTaskSource;

  /// No description provided for @healthCreateTaskNoConnections.
  ///
  /// In en, this message translates to:
  /// **'No database connections on the server yet. Add one under \"Server connections\".'**
  String get healthCreateTaskNoConnections;

  /// No description provided for @healthCreateTaskCron.
  ///
  /// In en, this message translates to:
  /// **'Cron schedule'**
  String get healthCreateTaskCron;

  /// No description provided for @healthCreateTaskCronHint.
  ///
  /// In en, this message translates to:
  /// **'5-field cron, e.g. */5 * * * * (every 5 minutes)'**
  String get healthCreateTaskCronHint;

  /// No description provided for @healthCreateTaskInvalidCron.
  ///
  /// In en, this message translates to:
  /// **'Enter a valid 5-field cron expression.'**
  String get healthCreateTaskInvalidCron;

  /// No description provided for @healthCreateTaskFailThreshold.
  ///
  /// In en, this message translates to:
  /// **'Alert threshold'**
  String get healthCreateTaskFailThreshold;

  /// No description provided for @healthCreateTaskFailThresholdHint.
  ///
  /// In en, this message translates to:
  /// **'Consecutive failures before alerting (1-10)'**
  String get healthCreateTaskFailThresholdHint;

  /// No description provided for @healthCreateTaskInvalidFailThreshold.
  ///
  /// In en, this message translates to:
  /// **'Threshold must be between 1 and 10.'**
  String get healthCreateTaskInvalidFailThreshold;

  /// No description provided for @healthCreateTaskWebhook.
  ///
  /// In en, this message translates to:
  /// **'Webhook URL (optional)'**
  String get healthCreateTaskWebhook;

  /// No description provided for @healthCreateTaskWebhookHint.
  ///
  /// In en, this message translates to:
  /// **'https:// URL to receive health alerts.'**
  String get healthCreateTaskWebhookHint;

  /// No description provided for @healthCreateTaskInvalidWebhook.
  ///
  /// In en, this message translates to:
  /// **'Webhook must be an https:// URL.'**
  String get healthCreateTaskInvalidWebhook;

  /// No description provided for @healthCreateTaskSubmit.
  ///
  /// In en, this message translates to:
  /// **'Create Task'**
  String get healthCreateTaskSubmit;

  /// No description provided for @healthCreateTaskButton.
  ///
  /// In en, this message translates to:
  /// **'New Task'**
  String get healthCreateTaskButton;

  /// No description provided for @healthGatedTitle.
  ///
  /// In en, this message translates to:
  /// **'Server license gated'**
  String get healthGatedTitle;

  /// No description provided for @healthGatedBody.
  ///
  /// In en, this message translates to:
  /// **'Activate or renew the Server license to create health check tasks. Existing data is still visible.'**
  String get healthGatedBody;

  /// No description provided for @healthHistoryTitle.
  ///
  /// In en, this message translates to:
  /// **'Run History'**
  String get healthHistoryTitle;

  /// No description provided for @healthViewAllHistory.
  ///
  /// In en, this message translates to:
  /// **'View full history'**
  String get healthViewAllHistory;

  /// No description provided for @healthHistoryError.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String healthHistoryError(String error);

  /// No description provided for @healthTriggerManual.
  ///
  /// In en, this message translates to:
  /// **'Manual'**
  String get healthTriggerManual;

  /// No description provided for @healthTriggerScheduler.
  ///
  /// In en, this message translates to:
  /// **'Scheduled'**
  String get healthTriggerScheduler;

  /// No description provided for @dataSyncCreateTaskButton.
  ///
  /// In en, this message translates to:
  /// **'New Sync Task'**
  String get dataSyncCreateTaskButton;

  /// No description provided for @taskEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit Task'**
  String get taskEditTitle;

  /// No description provided for @taskEditName.
  ///
  /// In en, this message translates to:
  /// **'Task name'**
  String get taskEditName;

  /// No description provided for @taskEditInvalidName.
  ///
  /// In en, this message translates to:
  /// **'Name cannot be empty'**
  String get taskEditInvalidName;

  /// No description provided for @taskEditEnabled.
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get taskEditEnabled;

  /// No description provided for @taskEditEnabledHint.
  ///
  /// In en, this message translates to:
  /// **'Schedule is active (cron fires as configured)'**
  String get taskEditEnabledHint;

  /// No description provided for @taskEditDisabledHint.
  ///
  /// In en, this message translates to:
  /// **'Paused — cron will not fire'**
  String get taskEditDisabledHint;

  /// No description provided for @taskEditCron.
  ///
  /// In en, this message translates to:
  /// **'Cron expression'**
  String get taskEditCron;

  /// No description provided for @taskEditCronHint.
  ///
  /// In en, this message translates to:
  /// **'5 fields: minute hour day month weekday (e.g. */5 * * * *)'**
  String get taskEditCronHint;

  /// No description provided for @taskEditInvalidCron.
  ///
  /// In en, this message translates to:
  /// **'Enter 5 space-separated fields'**
  String get taskEditInvalidCron;

  /// No description provided for @taskEditWebhook.
  ///
  /// In en, this message translates to:
  /// **'Webhook URL'**
  String get taskEditWebhook;

  /// No description provided for @taskEditWebhookHint.
  ///
  /// In en, this message translates to:
  /// **'Optional HTTPS webhooks — comma-separated for multiple'**
  String get taskEditWebhookHint;

  /// No description provided for @taskEditInvalidWebhook.
  ///
  /// In en, this message translates to:
  /// **'Must start with https://'**
  String get taskEditInvalidWebhook;

  /// No description provided for @taskEditCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get taskEditCancel;

  /// No description provided for @taskEditSubmit.
  ///
  /// In en, this message translates to:
  /// **'Save Changes'**
  String get taskEditSubmit;

  /// No description provided for @taskTogglePauseTooltip.
  ///
  /// In en, this message translates to:
  /// **'Pause schedule'**
  String get taskTogglePauseTooltip;

  /// No description provided for @taskToggleResumeTooltip.
  ///
  /// In en, this message translates to:
  /// **'Resume schedule'**
  String get taskToggleResumeTooltip;

  /// No description provided for @taskEditTooltip.
  ///
  /// In en, this message translates to:
  /// **'Edit task'**
  String get taskEditTooltip;

  /// No description provided for @taskDeleteTooltip.
  ///
  /// In en, this message translates to:
  /// **'Delete task'**
  String get taskDeleteTooltip;

  /// No description provided for @taskDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this task? This cannot be undone.'**
  String get taskDeleteConfirm;

  /// No description provided for @teamQueryTitle.
  ///
  /// In en, this message translates to:
  /// **'Team Query Library'**
  String get teamQueryTitle;

  /// No description provided for @teamQueryRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get teamQueryRefresh;

  /// No description provided for @teamQuerySearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search title or SQL…'**
  String get teamQuerySearchHint;

  /// No description provided for @teamQueryTagHint.
  ///
  /// In en, this message translates to:
  /// **'Filter by tag'**
  String get teamQueryTagHint;

  /// No description provided for @teamQueryEmpty.
  ///
  /// In en, this message translates to:
  /// **'No team queries yet. Publish one from the editor.'**
  String get teamQueryEmpty;

  /// No description provided for @teamQueryNotConnected.
  ///
  /// In en, this message translates to:
  /// **'Not connected to a DbMaster server.'**
  String get teamQueryNotConnected;

  /// No description provided for @teamQueryFork.
  ///
  /// In en, this message translates to:
  /// **'Open (fork to editor)'**
  String get teamQueryFork;

  /// No description provided for @teamQueryDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get teamQueryDelete;

  /// No description provided for @teamQueryCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get teamQueryCancel;

  /// No description provided for @teamQueryDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete \"{title}\" from the team library?'**
  String teamQueryDeleteConfirm(String title);

  /// No description provided for @teamQueryForkNoConnection.
  ///
  /// In en, this message translates to:
  /// **'Open a database connection first, then fork a team query.'**
  String get teamQueryForkNoConnection;

  /// No description provided for @teamQueryForked.
  ///
  /// In en, this message translates to:
  /// **'Opened \"{title}\" in a new tab.'**
  String teamQueryForked(String title);

  /// No description provided for @teamQueryCreatedBy.
  ///
  /// In en, this message translates to:
  /// **'by {author}'**
  String teamQueryCreatedBy(String author);

  /// No description provided for @teamQueryMenuLabel.
  ///
  /// In en, this message translates to:
  /// **'Team Query Library'**
  String get teamQueryMenuLabel;

  /// No description provided for @saveToTeamTooltip.
  ///
  /// In en, this message translates to:
  /// **'Save to Team Library'**
  String get saveToTeamTooltip;

  /// No description provided for @saveToTeamTitle.
  ///
  /// In en, this message translates to:
  /// **'Publish to Team Library'**
  String get saveToTeamTitle;

  /// No description provided for @saveToTeamNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Query name'**
  String get saveToTeamNameLabel;

  /// No description provided for @saveToTeamTagsLabel.
  ///
  /// In en, this message translates to:
  /// **'Tags (comma-separated)'**
  String get saveToTeamTagsLabel;

  /// No description provided for @saveToTeamTagsHint.
  ///
  /// In en, this message translates to:
  /// **'Optional — helps teammates find this query'**
  String get saveToTeamTagsHint;

  /// No description provided for @saveToTeamCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get saveToTeamCancel;

  /// No description provided for @saveToTeamSubmit.
  ///
  /// In en, this message translates to:
  /// **'Publish'**
  String get saveToTeamSubmit;

  /// No description provided for @saveToTeamSuccess.
  ///
  /// In en, this message translates to:
  /// **'Published \"{title}\" to the team library.'**
  String saveToTeamSuccess(String title);

  /// No description provided for @saveToTeamGated.
  ///
  /// In en, this message translates to:
  /// **'License gated — activate the Server license to publish team queries.'**
  String get saveToTeamGated;

  /// No description provided for @approvalMenuLabel.
  ///
  /// In en, this message translates to:
  /// **'DDL Approvals'**
  String get approvalMenuLabel;

  /// No description provided for @approvalListTitle.
  ///
  /// In en, this message translates to:
  /// **'DDL Approvals'**
  String get approvalListTitle;

  /// No description provided for @approvalAddTooltip.
  ///
  /// In en, this message translates to:
  /// **'Submit new DDL'**
  String get approvalAddTooltip;

  /// No description provided for @approvalRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get approvalRefresh;

  /// No description provided for @approvalNotConnected.
  ///
  /// In en, this message translates to:
  /// **'Connect to a DbMaster server to view approvals.'**
  String get approvalNotConnected;

  /// No description provided for @approvalListEmpty.
  ///
  /// In en, this message translates to:
  /// **'No DDL approvals.'**
  String get approvalListEmpty;

  /// No description provided for @approvalSubmitTitle.
  ///
  /// In en, this message translates to:
  /// **'Submit DDL for Approval'**
  String get approvalSubmitTitle;

  /// No description provided for @approvalSubmitButton.
  ///
  /// In en, this message translates to:
  /// **'Submit for Approval'**
  String get approvalSubmitButton;

  /// No description provided for @approvalSubmitDdlLabel.
  ///
  /// In en, this message translates to:
  /// **'DDL Statement'**
  String get approvalSubmitDdlLabel;

  /// No description provided for @approvalSubmitDdlHint.
  ///
  /// In en, this message translates to:
  /// **'Paste the DDL to submit for review'**
  String get approvalSubmitDdlHint;

  /// No description provided for @approvalSubmitRequired.
  ///
  /// In en, this message translates to:
  /// **'DDL statement is required'**
  String get approvalSubmitRequired;

  /// No description provided for @approvalSubmitInvalidSql.
  ///
  /// In en, this message translates to:
  /// **'Does not look like DDL (expected CREATE/ALTER/DROP/TRUNCATE/RENAME)'**
  String get approvalSubmitInvalidSql;

  /// No description provided for @approvalSubmitTargetDb.
  ///
  /// In en, this message translates to:
  /// **'Target Connection'**
  String get approvalSubmitTargetDb;

  /// No description provided for @approvalSubmitNoConnection.
  ///
  /// In en, this message translates to:
  /// **'No server connections available. Add one under \"Server connections\".'**
  String get approvalSubmitNoConnection;

  /// No description provided for @approvalSubmitSuccess.
  ///
  /// In en, this message translates to:
  /// **'DDL submitted for approval.'**
  String get approvalSubmitSuccess;

  /// No description provided for @approvalLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get approvalLoading;

  /// No description provided for @approvalCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get approvalCancel;

  /// No description provided for @approvalApprove.
  ///
  /// In en, this message translates to:
  /// **'Approve & Execute'**
  String get approvalApprove;

  /// No description provided for @approvalReject.
  ///
  /// In en, this message translates to:
  /// **'Reject'**
  String get approvalReject;

  /// No description provided for @approvalRejectTitle.
  ///
  /// In en, this message translates to:
  /// **'Reject Approval'**
  String get approvalRejectTitle;

  /// No description provided for @approvalRejectConfirm.
  ///
  /// In en, this message translates to:
  /// **'Reject this DDL approval? The Server will not execute the DDL. This cannot be undone.'**
  String get approvalRejectConfirm;

  /// No description provided for @approvalViewDdl.
  ///
  /// In en, this message translates to:
  /// **'View DDL'**
  String get approvalViewDdl;

  /// No description provided for @approvalStatusPending.
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get approvalStatusPending;

  /// No description provided for @approvalStatusExecuting.
  ///
  /// In en, this message translates to:
  /// **'Executing'**
  String get approvalStatusExecuting;

  /// No description provided for @approvalStatusApproved.
  ///
  /// In en, this message translates to:
  /// **'Approved'**
  String get approvalStatusApproved;

  /// No description provided for @approvalStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get approvalStatusFailed;

  /// No description provided for @approvalStatusRejected.
  ///
  /// In en, this message translates to:
  /// **'Rejected'**
  String get approvalStatusRejected;

  /// No description provided for @approvalExecError.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String approvalExecError(String error);

  /// No description provided for @approvalAlreadyResolved.
  ///
  /// In en, this message translates to:
  /// **'This approval was already resolved by another reviewer.'**
  String get approvalAlreadyResolved;

  /// No description provided for @approvalConflict.
  ///
  /// In en, this message translates to:
  /// **'Another reviewer claimed this approval first.'**
  String get approvalConflict;

  /// No description provided for @approvalNotFound.
  ///
  /// In en, this message translates to:
  /// **'Approval not found (it may have been deleted).'**
  String get approvalNotFound;

  /// No description provided for @approvalGatedTitle.
  ///
  /// In en, this message translates to:
  /// **'License Required'**
  String get approvalGatedTitle;

  /// No description provided for @approvalGatedBody.
  ///
  /// In en, this message translates to:
  /// **'Activate or renew the Server license to manage DDL approvals.'**
  String get approvalGatedBody;

  /// No description provided for @approvalMetaLine.
  ///
  /// In en, this message translates to:
  /// **'→ {target} • by {submitter}'**
  String approvalMetaLine(String target, String submitter);

  /// No description provided for @approvalBadgeCount.
  ///
  /// In en, this message translates to:
  /// **'{n} pending'**
  String approvalBadgeCount(int n);

  /// No description provided for @submitApprovalTooltip.
  ///
  /// In en, this message translates to:
  /// **'Submit DDL for Approval'**
  String get submitApprovalTooltip;

  /// No description provided for @workspacesMenuLabel.
  ///
  /// In en, this message translates to:
  /// **'Workspaces'**
  String get workspacesMenuLabel;

  /// No description provided for @workspacesTitle.
  ///
  /// In en, this message translates to:
  /// **'Workspaces'**
  String get workspacesTitle;

  /// No description provided for @workspacesRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get workspacesRefresh;

  /// No description provided for @workspacesCreate.
  ///
  /// In en, this message translates to:
  /// **'New workspace'**
  String get workspacesCreate;

  /// No description provided for @workspacesJoin.
  ///
  /// In en, this message translates to:
  /// **'Join workspace'**
  String get workspacesJoin;

  /// No description provided for @workspacesNotConnected.
  ///
  /// In en, this message translates to:
  /// **'Connect to a DbMaster server to manage workspaces.'**
  String get workspacesNotConnected;

  /// No description provided for @workspacesEmpty.
  ///
  /// In en, this message translates to:
  /// **'No workspaces yet. Create one or join with an invite code.'**
  String get workspacesEmpty;

  /// No description provided for @workspacesMembers.
  ///
  /// In en, this message translates to:
  /// **'Members'**
  String get workspacesMembers;

  /// No description provided for @workspacesLeave.
  ///
  /// In en, this message translates to:
  /// **'Leave'**
  String get workspacesLeave;

  /// No description provided for @workspacesDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get workspacesDelete;

  /// No description provided for @workspacesMemberCount.
  ///
  /// In en, this message translates to:
  /// **'{n} members'**
  String workspacesMemberCount(int n);

  /// No description provided for @workspacesRoleAdmin.
  ///
  /// In en, this message translates to:
  /// **'Admin'**
  String get workspacesRoleAdmin;

  /// No description provided for @workspacesScopeNotice.
  ///
  /// In en, this message translates to:
  /// **'Workspaces are member groups for inviting collaborators. Automation tasks, connections, and the team query library are shared across the whole server instance — they are not isolated per workspace.'**
  String get workspacesScopeNotice;

  /// No description provided for @workspacesRoleMember.
  ///
  /// In en, this message translates to:
  /// **'Member'**
  String get workspacesRoleMember;

  /// No description provided for @workspacesLeaveConfirm.
  ///
  /// In en, this message translates to:
  /// **'Leave workspace \"{name}\"?'**
  String workspacesLeaveConfirm(String name);

  /// No description provided for @workspacesDeleteConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete workspace \"{name}\"? This removes all members.'**
  String workspacesDeleteConfirm(String name);

  /// No description provided for @workspacesCreated.
  ///
  /// In en, this message translates to:
  /// **'Created workspace \"{name}\".'**
  String workspacesCreated(String name);

  /// No description provided for @workspacesLeft.
  ///
  /// In en, this message translates to:
  /// **'Left workspace \"{name}\".'**
  String workspacesLeft(String name);

  /// No description provided for @workspacesDeleted.
  ///
  /// In en, this message translates to:
  /// **'Deleted workspace \"{name}\".'**
  String workspacesDeleted(String name);

  /// No description provided for @workspacesJoined.
  ///
  /// In en, this message translates to:
  /// **'Joined workspace.'**
  String get workspacesJoined;

  /// No description provided for @workspacesCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get workspacesCancel;

  /// No description provided for @workspacesCreateTitle.
  ///
  /// In en, this message translates to:
  /// **'New Workspace'**
  String get workspacesCreateTitle;

  /// No description provided for @workspacesCreateNameLabel.
  ///
  /// In en, this message translates to:
  /// **'Workspace name'**
  String get workspacesCreateNameLabel;

  /// No description provided for @workspacesCreateNameHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. Data Platform Team'**
  String get workspacesCreateNameHint;

  /// No description provided for @workspacesCreateRequired.
  ///
  /// In en, this message translates to:
  /// **'Name is required.'**
  String get workspacesCreateRequired;

  /// No description provided for @workspacesCreateTooLong.
  ///
  /// In en, this message translates to:
  /// **'Name must be 100 characters or fewer.'**
  String get workspacesCreateTooLong;

  /// No description provided for @workspacesCreateButton.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get workspacesCreateButton;

  /// No description provided for @workspacesJoinTitle.
  ///
  /// In en, this message translates to:
  /// **'Join Workspace'**
  String get workspacesJoinTitle;

  /// No description provided for @workspacesJoinIdLabel.
  ///
  /// In en, this message translates to:
  /// **'Workspace ID'**
  String get workspacesJoinIdLabel;

  /// No description provided for @workspacesJoinIdHint.
  ///
  /// In en, this message translates to:
  /// **'Paste the workspace ID shared by an admin'**
  String get workspacesJoinIdHint;

  /// No description provided for @workspacesJoinCodeLabel.
  ///
  /// In en, this message translates to:
  /// **'Invite code'**
  String get workspacesJoinCodeLabel;

  /// No description provided for @workspacesJoinCodeHint.
  ///
  /// In en, this message translates to:
  /// **'6-character code'**
  String get workspacesJoinCodeHint;

  /// No description provided for @workspacesJoinRequired.
  ///
  /// In en, this message translates to:
  /// **'Both fields are required.'**
  String get workspacesJoinRequired;

  /// No description provided for @workspacesJoinHint.
  ///
  /// In en, this message translates to:
  /// **'Ask a workspace admin for the Workspace ID and invite code, then paste both above.'**
  String get workspacesJoinHint;

  /// No description provided for @workspacesJoinButton.
  ///
  /// In en, this message translates to:
  /// **'Join'**
  String get workspacesJoinButton;

  /// No description provided for @workspacesMembersTitle.
  ///
  /// In en, this message translates to:
  /// **'Members — {name}'**
  String workspacesMembersTitle(String name);

  /// No description provided for @workspacesInviteCode.
  ///
  /// In en, this message translates to:
  /// **'Invite code'**
  String get workspacesInviteCode;

  /// No description provided for @workspacesCopyInvite.
  ///
  /// In en, this message translates to:
  /// **'Copy invite'**
  String get workspacesCopyInvite;

  /// No description provided for @workspacesInviteCopied.
  ///
  /// In en, this message translates to:
  /// **'Workspace ID + invite code copied to share.'**
  String get workspacesInviteCopied;

  /// No description provided for @workspacesMembersEmpty.
  ///
  /// In en, this message translates to:
  /// **'No members.'**
  String get workspacesMembersEmpty;

  /// No description provided for @workspacesRemoveMember.
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get workspacesRemoveMember;

  /// No description provided for @workspacesRemoveMemberConfirm.
  ///
  /// In en, this message translates to:
  /// **'Remove {name} from this workspace?'**
  String workspacesRemoveMemberConfirm(String name);

  /// No description provided for @workspacesYou.
  ///
  /// In en, this message translates to:
  /// **'(you)'**
  String get workspacesYou;

  /// No description provided for @layoutInsufficientSpace.
  ///
  /// In en, this message translates to:
  /// **'Not enough space to expand this panel — enlarge the window'**
  String get layoutInsufficientSpace;

  /// No description provided for @welcomeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'AI-enhanced database management'**
  String get welcomeSubtitle;

  /// No description provided for @mcpTokensMenuLabel.
  ///
  /// In en, this message translates to:
  /// **'MCP Tokens'**
  String get mcpTokensMenuLabel;

  /// No description provided for @mcpTokensTitle.
  ///
  /// In en, this message translates to:
  /// **'MCP Tokens'**
  String get mcpTokensTitle;

  /// No description provided for @mcpTokensIntro.
  ///
  /// In en, this message translates to:
  /// **'Long-lived tokens for AI clients (Claude Code, Cursor). Paste one as the Bearer token in the client\'s MCP config; revoke any time.'**
  String get mcpTokensIntro;

  /// No description provided for @mcpTokensNotConnected.
  ///
  /// In en, this message translates to:
  /// **'Connect to a DbMaster server to manage MCP tokens.'**
  String get mcpTokensNotConnected;

  /// No description provided for @mcpTokensEmpty.
  ///
  /// In en, this message translates to:
  /// **'No tokens yet. Create one for your AI client.'**
  String get mcpTokensEmpty;

  /// No description provided for @mcpTokensNameHint.
  ///
  /// In en, this message translates to:
  /// **'Token name (e.g. claude-code-mac)'**
  String get mcpTokensNameHint;

  /// No description provided for @mcpTokensCreate.
  ///
  /// In en, this message translates to:
  /// **'Create'**
  String get mcpTokensCreate;

  /// No description provided for @mcpTokensOnceTitle.
  ///
  /// In en, this message translates to:
  /// **'Token \"{name}\" created'**
  String mcpTokensOnceTitle(String name);

  /// No description provided for @mcpTokensOnceWarning.
  ///
  /// In en, this message translates to:
  /// **'Copy it now — for security it will never be shown again. Use it as the Bearer token in your MCP client config (e.g. mcp.json).'**
  String get mcpTokensOnceWarning;

  /// No description provided for @mcpTokensCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get mcpTokensCopy;

  /// No description provided for @mcpTokensCopied.
  ///
  /// In en, this message translates to:
  /// **'Token copied to clipboard'**
  String get mcpTokensCopied;

  /// No description provided for @mcpTokensDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get mcpTokensDone;

  /// No description provided for @mcpTokensLastUsed.
  ///
  /// In en, this message translates to:
  /// **'Last used: {value}'**
  String mcpTokensLastUsed(String value);

  /// No description provided for @mcpTokensNeverUsed.
  ///
  /// In en, this message translates to:
  /// **'never'**
  String get mcpTokensNeverUsed;

  /// No description provided for @mcpTokensRevoke.
  ///
  /// In en, this message translates to:
  /// **'Revoke'**
  String get mcpTokensRevoke;

  /// No description provided for @mcpTokensRevokeTitle.
  ///
  /// In en, this message translates to:
  /// **'Revoke this token?'**
  String get mcpTokensRevokeTitle;

  /// No description provided for @mcpTokensRevokeBody.
  ///
  /// In en, this message translates to:
  /// **'Clients using \"{name}\" ({prefix}…) will stop working immediately. This cannot be undone.'**
  String mcpTokensRevokeBody(String name, String prefix);

  /// No description provided for @serverConnectionsMenuLabel.
  ///
  /// In en, this message translates to:
  /// **'Server connections'**
  String get serverConnectionsMenuLabel;

  /// No description provided for @serverConnectionsTitle.
  ///
  /// In en, this message translates to:
  /// **'Server connections'**
  String get serverConnectionsTitle;

  /// No description provided for @serverConnectionsIntro.
  ///
  /// In en, this message translates to:
  /// **'Connections registered on the server. Data sync, health checks and DDL approvals run against these; the desktop sidebar list is separate.'**
  String get serverConnectionsIntro;

  /// No description provided for @serverConnectionsNotConnected.
  ///
  /// In en, this message translates to:
  /// **'Not connected to a server.'**
  String get serverConnectionsNotConnected;

  /// No description provided for @serverConnectionsEmpty.
  ///
  /// In en, this message translates to:
  /// **'No server connections yet. Add one so data sync / health check / approval tasks have a database to run against.'**
  String get serverConnectionsEmpty;

  /// No description provided for @serverConnectionsAdd.
  ///
  /// In en, this message translates to:
  /// **'Add'**
  String get serverConnectionsAdd;

  /// No description provided for @serverConnectionsEdit.
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get serverConnectionsEdit;

  /// No description provided for @serverConnectionsDelete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get serverConnectionsDelete;

  /// No description provided for @serverConnectionsKindCollab.
  ///
  /// In en, this message translates to:
  /// **'collab'**
  String get serverConnectionsKindCollab;

  /// No description provided for @serverConnectionsKindSourceDrift.
  ///
  /// In en, this message translates to:
  /// **'drift source (read-only)'**
  String get serverConnectionsKindSourceDrift;

  /// No description provided for @serverConnectionsDeleteTitle.
  ///
  /// In en, this message translates to:
  /// **'Delete connection'**
  String get serverConnectionsDeleteTitle;

  /// No description provided for @serverConnectionsDeleteBody.
  ///
  /// In en, this message translates to:
  /// **'Delete server connection \"{name}\"?'**
  String serverConnectionsDeleteBody(String name);

  /// No description provided for @serverConnectionsDeleteTaskWarning.
  ///
  /// In en, this message translates to:
  /// **'{count} task(s) reference this connection and will be deleted (as source) or detached (as target).'**
  String serverConnectionsDeleteTaskWarning(num count);

  /// No description provided for @serverConnFormCreateTitle.
  ///
  /// In en, this message translates to:
  /// **'Add server connection'**
  String get serverConnFormCreateTitle;

  /// No description provided for @serverConnFormEditTitle.
  ///
  /// In en, this message translates to:
  /// **'Edit server connection'**
  String get serverConnFormEditTitle;

  /// No description provided for @serverConnFormName.
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get serverConnFormName;

  /// No description provided for @serverConnFormType.
  ///
  /// In en, this message translates to:
  /// **'Type'**
  String get serverConnFormType;

  /// No description provided for @serverConnFormHost.
  ///
  /// In en, this message translates to:
  /// **'Host'**
  String get serverConnFormHost;

  /// No description provided for @serverConnFormPort.
  ///
  /// In en, this message translates to:
  /// **'Port'**
  String get serverConnFormPort;

  /// No description provided for @serverConnFormUsername.
  ///
  /// In en, this message translates to:
  /// **'Username'**
  String get serverConnFormUsername;

  /// No description provided for @serverConnFormPassword.
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get serverConnFormPassword;

  /// No description provided for @serverConnFormPasswordKeepHint.
  ///
  /// In en, this message translates to:
  /// **'Leave blank to keep the stored password'**
  String get serverConnFormPasswordKeepHint;

  /// No description provided for @serverConnFormDatabase.
  ///
  /// In en, this message translates to:
  /// **'Default database (optional)'**
  String get serverConnFormDatabase;

  /// No description provided for @serverConnFormSqlitePath.
  ///
  /// In en, this message translates to:
  /// **'Database file path'**
  String get serverConnFormSqlitePath;

  /// No description provided for @serverConnFormSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get serverConnFormSave;

  /// No description provided for @serverConnFormRequired.
  ///
  /// In en, this message translates to:
  /// **'Required'**
  String get serverConnFormRequired;

  /// No description provided for @serverConnFormInvalidPort.
  ///
  /// In en, this message translates to:
  /// **'Port must be a number'**
  String get serverConnFormInvalidPort;

  /// No description provided for @dataSyncConnectionNotOnServer.
  ///
  /// In en, this message translates to:
  /// **'The selected connection is not registered on the server. Add it under \"Server connections\" first, then retry.'**
  String get dataSyncConnectionNotOnServer;

  /// No description provided for @settingsLogs.
  ///
  /// In en, this message translates to:
  /// **'Logs'**
  String get settingsLogs;

  /// No description provided for @logsUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Logging unavailable'**
  String get logsUnavailable;

  /// No description provided for @logsOpenFolder.
  ///
  /// In en, this message translates to:
  /// **'Open Folder'**
  String get logsOpenFolder;

  /// No description provided for @logsExport.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get logsExport;

  /// No description provided for @logsExportSuccess.
  ///
  /// In en, this message translates to:
  /// **'Log exported'**
  String get logsExportSuccess;

  /// No description provided for @logsExportFailed.
  ///
  /// In en, this message translates to:
  /// **'Export failed: {error}'**
  String logsExportFailed(String error);

  /// No description provided for @logsOpenFolderFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to open folder'**
  String get logsOpenFolderFailed;

  /// No description provided for @updateSectionTitle.
  ///
  /// In en, this message translates to:
  /// **'Updates'**
  String get updateSectionTitle;

  /// No description provided for @updateCheckButton.
  ///
  /// In en, this message translates to:
  /// **'Check'**
  String get updateCheckButton;

  /// No description provided for @updateGoDownload.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get updateGoDownload;

  /// No description provided for @updateStatusChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking…'**
  String get updateStatusChecking;

  /// No description provided for @updateStatusUpToDate.
  ///
  /// In en, this message translates to:
  /// **'You\'re up to date'**
  String get updateStatusUpToDate;

  /// No description provided for @updateStatusAvailable.
  ///
  /// In en, this message translates to:
  /// **'New version available: {version}'**
  String updateStatusAvailable(String version);

  /// No description provided for @updateStatusUnknownVersion.
  ///
  /// In en, this message translates to:
  /// **'Current version unknown (development build)'**
  String get updateStatusUnknownVersion;

  /// No description provided for @updateStatusUnknownLatest.
  ///
  /// In en, this message translates to:
  /// **'Latest release: {version} (current version unknown)'**
  String updateStatusUnknownLatest(String version);

  /// No description provided for @updateStatusFailed.
  ///
  /// In en, this message translates to:
  /// **'Check failed — try again later'**
  String get updateStatusFailed;

  /// No description provided for @updateCurrentVersion.
  ///
  /// In en, this message translates to:
  /// **'Current version: {version}'**
  String updateCurrentVersion(String version);

  /// No description provided for @updateAutoCheck.
  ///
  /// In en, this message translates to:
  /// **'Check for updates on startup'**
  String get updateAutoCheck;

  /// No description provided for @updateAutoCheckDesc.
  ///
  /// In en, this message translates to:
  /// **'Silent check (at most once every 24h) against GitHub Releases'**
  String get updateAutoCheckDesc;

  /// No description provided for @serverVersionLine.
  ///
  /// In en, this message translates to:
  /// **'Server version: {version}'**
  String serverVersionLine(String version);

  /// No description provided for @serverVersionOutdated.
  ///
  /// In en, this message translates to:
  /// **'Server {version} is below the minimum compatible {min} — please upgrade dbmaster-server'**
  String serverVersionOutdated(String version, String min);

  /// No description provided for @updateAvailableSnackbar.
  ///
  /// In en, this message translates to:
  /// **'New version {version} is available'**
  String updateAvailableSnackbar(String version);

  /// No description provided for @crashRestoredTabs.
  ///
  /// In en, this message translates to:
  /// **'The app exited unexpectedly last time — recovered {count} tab(s)'**
  String crashRestoredTabs(int count);

  /// No description provided for @saveQueryNoConnection.
  ///
  /// In en, this message translates to:
  /// **'Cannot save — no database connection'**
  String get saveQueryNoConnection;

  /// No description provided for @saveQueryReadOnly.
  ///
  /// In en, this message translates to:
  /// **'Cannot save — this connection is read-only'**
  String get saveQueryReadOnly;

  /// No description provided for @saveQueryFailed.
  ///
  /// In en, this message translates to:
  /// **'Save failed: {error}'**
  String saveQueryFailed(String error);

  /// No description provided for @editorSuggestionApplied.
  ///
  /// In en, this message translates to:
  /// **'✓ Suggestion applied — SQL updated'**
  String get editorSuggestionApplied;

  /// No description provided for @editorRestoreOriginalSql.
  ///
  /// In en, this message translates to:
  /// **'Restore original SQL'**
  String get editorRestoreOriginalSql;

  /// No description provided for @editorIndexDdlFilled.
  ///
  /// In en, this message translates to:
  /// **'✓ Index DDL inserted — press Run to execute (safety review will apply)'**
  String get editorIndexDdlFilled;

  /// No description provided for @safetyReviewedLabel.
  ///
  /// In en, this message translates to:
  /// **'Reviewed'**
  String get safetyReviewedLabel;

  /// No description provided for @statusConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get statusConnecting;

  /// No description provided for @resultsContextCopyCell.
  ///
  /// In en, this message translates to:
  /// **'Copy Cell'**
  String get resultsContextCopyCell;

  /// No description provided for @resultsContextCopyRowJson.
  ///
  /// In en, this message translates to:
  /// **'Copy Row (JSON)'**
  String get resultsContextCopyRowJson;

  /// No description provided for @resultsContextExportRowInsert.
  ///
  /// In en, this message translates to:
  /// **'Export Row as SQL INSERT'**
  String get resultsContextExportRowInsert;

  /// No description provided for @resultsContextExportAllInsert.
  ///
  /// In en, this message translates to:
  /// **'Export All as SQL INSERT'**
  String get resultsContextExportAllInsert;

  /// No description provided for @resultsExtractNoKeys.
  ///
  /// In en, this message translates to:
  /// **'No top-level keys found'**
  String get resultsExtractNoKeys;

  /// No description provided for @resultsExtractFieldTitle.
  ///
  /// In en, this message translates to:
  /// **'Extract field from \"{column}\"'**
  String resultsExtractFieldTitle(String column);

  /// No description provided for @resultsCopiedExpression.
  ///
  /// In en, this message translates to:
  /// **'Copied: {expression}'**
  String resultsCopiedExpression(String expression);

  /// No description provided for @resultsExtractInvalidJson.
  ///
  /// In en, this message translates to:
  /// **'Invalid JSON'**
  String get resultsExtractInvalidJson;

  /// No description provided for @resultsInsertNoTableName.
  ///
  /// In en, this message translates to:
  /// **'Cannot determine table name from query'**
  String get resultsInsertNoTableName;

  /// No description provided for @resultsInsertRowDone.
  ///
  /// In en, this message translates to:
  /// **'Row exported as SQL INSERT to clipboard'**
  String get resultsInsertRowDone;

  /// No description provided for @resultsInsertNoData.
  ///
  /// In en, this message translates to:
  /// **'No data to export'**
  String get resultsInsertNoData;

  /// No description provided for @resultsInsertAllDone.
  ///
  /// In en, this message translates to:
  /// **'{count} rows exported as SQL INSERT to clipboard'**
  String resultsInsertAllDone(int count);

  /// No description provided for @connectionFailedWith.
  ///
  /// In en, this message translates to:
  /// **'Connection failed: {error}'**
  String connectionFailedWith(String error);

  /// No description provided for @viewTableDdl.
  ///
  /// In en, this message translates to:
  /// **'View DDL'**
  String get viewTableDdl;

  /// No description provided for @aboutVersionLine.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String aboutVersionLine(String version);

  /// No description provided for @aboutFeedback.
  ///
  /// In en, this message translates to:
  /// **'Feedback'**
  String get aboutFeedback;

  /// No description provided for @driftHistoryBaseline.
  ///
  /// In en, this message translates to:
  /// **'Baseline established'**
  String get driftHistoryBaseline;

  /// No description provided for @driftDiffOnlyBaseline.
  ///
  /// In en, this message translates to:
  /// **'Only the baseline snapshot exists so far — the next run will diff against it. Drift detection starts from the second snapshot.'**
  String get driftDiffOnlyBaseline;

  /// No description provided for @mcpTokensCreatedAt.
  ///
  /// In en, this message translates to:
  /// **'Created {time}'**
  String mcpTokensCreatedAt(String time);

  /// No description provided for @mcpTokensEndpointHint.
  ///
  /// In en, this message translates to:
  /// **'Configure this endpoint URL + the token (Bearer) in your MCP client (e.g. mcp.json):'**
  String get mcpTokensEndpointHint;

  /// No description provided for @mcpTokensEndpointCopied.
  ///
  /// In en, this message translates to:
  /// **'Endpoint copied'**
  String get mcpTokensEndpointCopied;

  /// No description provided for @historyLoadMore.
  ///
  /// In en, this message translates to:
  /// **'Load more'**
  String get historyLoadMore;

  /// Connection form footer: which plugin provides the current form
  ///
  /// In en, this message translates to:
  /// **'Provided by {plugin}'**
  String connectionFormProvidedBy(String plugin);

  /// Redis database index field label
  ///
  /// In en, this message translates to:
  /// **'Database Index'**
  String get connectionDbIndex;

  /// MongoDB authentication database field label
  ///
  /// In en, this message translates to:
  /// **'Authentication Database'**
  String get connectionAuthDatabase;

  /// Redis auth mode: no authentication
  ///
  /// In en, this message translates to:
  /// **'No Auth'**
  String get connectionRedisAuthNone;

  /// Redis auth mode description: no authentication required
  ///
  /// In en, this message translates to:
  /// **'No authentication required'**
  String get connectionRedisAuthNoneDesc;

  /// Redis auth mode: password only
  ///
  /// In en, this message translates to:
  /// **'Password Only'**
  String get connectionRedisAuthPasswordOnly;

  /// Redis auth mode description: AUTH password (pre-6.0)
  ///
  /// In en, this message translates to:
  /// **'AUTH password (Redis < 6.0)'**
  String get connectionRedisAuthPasswordOnlyDesc;

  /// Redis auth mode: username + password (ACL)
  ///
  /// In en, this message translates to:
  /// **'Username + Password (ACL)'**
  String get connectionRedisAuthUsernamePassword;

  /// Redis auth mode description: AUTH username password (Redis 6.0+ ACL)
  ///
  /// In en, this message translates to:
  /// **'AUTH username password (Redis 6.0+ ACL)'**
  String get connectionRedisAuthUsernamePasswordDesc;

  /// SSH auth mode: password
  ///
  /// In en, this message translates to:
  /// **'Password'**
  String get connectionSshAuthPassword;

  /// SSH auth mode: private key
  ///
  /// In en, this message translates to:
  /// **'Private Key'**
  String get connectionSshAuthPrivateKey;

  /// C14 sidebar capability menu section title
  ///
  /// In en, this message translates to:
  /// **'Capabilities'**
  String get sidebarCapabilityTitle;

  /// C14 capability menu group: database objects
  ///
  /// In en, this message translates to:
  /// **'Database Objects'**
  String get sidebarCapGroupDatabaseObjects;

  /// C14 capability menu group: advanced
  ///
  /// In en, this message translates to:
  /// **'Advanced'**
  String get sidebarCapGroupAdvanced;

  /// C17 redis capability menu group: keyspace
  ///
  /// In en, this message translates to:
  /// **'Keyspace'**
  String get redisCapGroupKeyspace;

  /// C17 redis capability item: CLI workbench panel
  ///
  /// In en, this message translates to:
  /// **'Command Line Workbench'**
  String get redisCapWorkbench;

  /// C17 redis capability item: pub/sub panel
  ///
  /// In en, this message translates to:
  /// **'Pub/Sub'**
  String get redisCapPubsub;

  /// C17 redis capability item: lua scripts panel
  ///
  /// In en, this message translates to:
  /// **'Lua Scripts'**
  String get redisCapLua;

  /// C17 redis capability item: pipeline panel
  ///
  /// In en, this message translates to:
  /// **'Pipeline'**
  String get redisCapPipeline;

  /// C17 redis capability item: MULTI-EXEC transaction panel
  ///
  /// In en, this message translates to:
  /// **'Transaction'**
  String get redisCapTransaction;

  /// C17 redis capability item: memory analysis panel
  ///
  /// In en, this message translates to:
  /// **'Memory Analysis'**
  String get redisCapMemoryAnalysis;

  /// C17 redis capability item: keyspace notifications panel
  ///
  /// In en, this message translates to:
  /// **'Keyspace Notifications'**
  String get redisCapKeyspaceNotifications;

  /// C17 redis capability item: ACL management panel
  ///
  /// In en, this message translates to:
  /// **'ACL Management'**
  String get redisCapAcl;

  /// C17 redis capability item: CONFIG SET edit dialog
  ///
  /// In en, this message translates to:
  /// **'Edit Config'**
  String get redisCapConfig;

  /// C17 mongo collection validation rules viewer title
  ///
  /// In en, this message translates to:
  /// **'Validation Rules'**
  String get mongoValidationTitle;

  /// C17 mongo validation viewer: no validator state
  ///
  /// In en, this message translates to:
  /// **'This collection has no validation rules configured (add via collMod or the MongoDB shell).'**
  String get mongoValidationNoValidator;

  /// C17 mongo validation viewer load failure
  ///
  /// In en, this message translates to:
  /// **'Failed to load validation rules: {error}'**
  String mongoValidationLoadFailed(String error);

  /// C17 snackbar after mongo document insert
  ///
  /// In en, this message translates to:
  /// **'Document inserted into {collection}'**
  String sidebarDocumentInserted(String collection);

  /// C23 skill catalog panel title
  ///
  /// In en, this message translates to:
  /// **'Skills'**
  String get aiSkillCatalogTitle;

  /// C23 skill catalog group: SQL
  ///
  /// In en, this message translates to:
  /// **'SQL'**
  String get aiSkillGroupSql;

  /// C23 skill catalog group: data
  ///
  /// In en, this message translates to:
  /// **'Data'**
  String get aiSkillGroupData;

  /// C23 skill catalog group: schema
  ///
  /// In en, this message translates to:
  /// **'Schema'**
  String get aiSkillGroupSchema;

  /// C23 skill catalog group: ops
  ///
  /// In en, this message translates to:
  /// **'Ops'**
  String get aiSkillGroupOps;

  /// C23 skill: nl2sql display name
  ///
  /// In en, this message translates to:
  /// **'Natural Language to SQL'**
  String get aiSkillNl2sqlName;

  /// C23 skill: nl2sql description
  ///
  /// In en, this message translates to:
  /// **'Describe what you want and get SQL'**
  String get aiSkillNl2sqlDesc;

  /// C23 skill: sql explain display name
  ///
  /// In en, this message translates to:
  /// **'SQL Explain'**
  String get aiSkillSqlExplainName;

  /// C23 skill: sql explain description
  ///
  /// In en, this message translates to:
  /// **'Walk through what a SQL statement does'**
  String get aiSkillSqlExplainDesc;

  /// C23 skill: sql explain prompt template
  ///
  /// In en, this message translates to:
  /// **'Explain what this SQL statement does, step by step:\n```\n\n```'**
  String get aiSkillSqlExplainPrompt;

  /// C23 skill: query optimizer display name
  ///
  /// In en, this message translates to:
  /// **'Query Optimizer'**
  String get aiSkillQueryOptimizerName;

  /// C23 skill: query optimizer description
  ///
  /// In en, this message translates to:
  /// **'Analyze a slow query and suggest optimizations'**
  String get aiSkillQueryOptimizerDesc;

  /// C23 skill: query optimizer prompt template
  ///
  /// In en, this message translates to:
  /// **'Analyze this query for performance issues and suggest optimizations:\n```\n\n```'**
  String get aiSkillQueryOptimizerPrompt;

  /// C23 skill: data cleaning display name
  ///
  /// In en, this message translates to:
  /// **'Data Cleaning Advice'**
  String get aiSkillDataCleaningName;

  /// C23 skill: data cleaning description
  ///
  /// In en, this message translates to:
  /// **'Suggest how to clean up dirty data in a table'**
  String get aiSkillDataCleaningDesc;

  /// C23 skill: data cleaning prompt template
  ///
  /// In en, this message translates to:
  /// **'Suggest cleaning steps for dirty data in my table. Known issues:'**
  String get aiSkillDataCleaningPrompt;

  /// C23 skill: import mapping display name
  ///
  /// In en, this message translates to:
  /// **'Import Mapping'**
  String get aiSkillImportMappingName;

  /// C23 skill: import mapping description
  ///
  /// In en, this message translates to:
  /// **'Generate a column mapping for data import'**
  String get aiSkillImportMappingDesc;

  /// C23 skill: import mapping prompt template
  ///
  /// In en, this message translates to:
  /// **'Generate a column mapping (JSON) to import the following file into the table.\nSource columns:\nTarget columns:'**
  String get aiSkillImportMappingPrompt;

  /// C23 skill: schema analysis display name
  ///
  /// In en, this message translates to:
  /// **'Schema Analysis'**
  String get aiSkillSchemaAnalysisName;

  /// C23 skill: schema analysis description
  ///
  /// In en, this message translates to:
  /// **'Review the current schema and point out risks'**
  String get aiSkillSchemaAnalysisDesc;

  /// C23 skill: schema analysis prompt template
  ///
  /// In en, this message translates to:
  /// **'Review the current database schema and point out design risks and improvements.'**
  String get aiSkillSchemaAnalysisPrompt;

  /// C23 skill: schema diff display name
  ///
  /// In en, this message translates to:
  /// **'Schema Diff Helper'**
  String get aiSkillSchemaDiffName;

  /// C23 skill: schema diff description
  ///
  /// In en, this message translates to:
  /// **'Compare two schema definitions and output a diff'**
  String get aiSkillSchemaDiffDesc;

  /// C23 skill: schema diff prompt template
  ///
  /// In en, this message translates to:
  /// **'Compare the following two schema definitions and output a unified diff:\n<schema-a>\n\n</schema-a>\n<schema-b>\n\n</schema-b>'**
  String get aiSkillSchemaDiffPrompt;

  /// C23 skill: index advice display name
  ///
  /// In en, this message translates to:
  /// **'Index Advice'**
  String get aiSkillIndexSuggestName;

  /// C23 skill: index advice description
  ///
  /// In en, this message translates to:
  /// **'Suggest indexes for a query or table'**
  String get aiSkillIndexSuggestDesc;

  /// C23 skill: index advice prompt template
  ///
  /// In en, this message translates to:
  /// **'Suggest indexes for this query and explain why:\n```\n\n```'**
  String get aiSkillIndexSuggestPrompt;

  /// C23 skill: error diagnosis display name
  ///
  /// In en, this message translates to:
  /// **'Error Diagnosis'**
  String get aiSkillErrorDiagnosisName;

  /// C23 skill: error diagnosis description
  ///
  /// In en, this message translates to:
  /// **'Diagnose a database error message'**
  String get aiSkillErrorDiagnosisDesc;

  /// C23 skill: error diagnosis prompt template
  ///
  /// In en, this message translates to:
  /// **'Diagnose this database error and suggest fixes:\n```\n\n```'**
  String get aiSkillErrorDiagnosisPrompt;

  /// C23 skill: slow query display name
  ///
  /// In en, this message translates to:
  /// **'Slow Query Analysis'**
  String get aiSkillSlowQueryName;

  /// C23 skill: slow query description
  ///
  /// In en, this message translates to:
  /// **'Analyze slow query log entries'**
  String get aiSkillSlowQueryDesc;

  /// C23 skill: slow query prompt template
  ///
  /// In en, this message translates to:
  /// **'Analyze this slow query log entry and locate the bottleneck:\n```\n\n```'**
  String get aiSkillSlowQueryPrompt;

  /// C23 context panel title
  ///
  /// In en, this message translates to:
  /// **'Context'**
  String get aiContextPanelTitle;

  /// C23 context panel section: current connection
  ///
  /// In en, this message translates to:
  /// **'Current Connection'**
  String get aiContextConnectionSection;

  /// C23 context panel section: current database
  ///
  /// In en, this message translates to:
  /// **'Current Database'**
  String get aiContextDatabaseSection;

  /// C23 context panel empty state
  ///
  /// In en, this message translates to:
  /// **'No connection selected'**
  String get aiContextNoConnection;

  /// C23 context panel toggle label
  ///
  /// In en, this message translates to:
  /// **'Include schema context'**
  String get aiContextSchemaContext;

  /// C23 context panel toggle description
  ///
  /// In en, this message translates to:
  /// **'Attach table schemas of the current database when sending'**
  String get aiContextSchemaContextDesc;

  /// C23 narrow-mode toolbar button: open skill catalog
  ///
  /// In en, this message translates to:
  /// **'Skill catalog'**
  String get aiPanelOpenSkillCatalog;

  /// C23 narrow-mode toolbar button: open context panel
  ///
  /// In en, this message translates to:
  /// **'Context panel'**
  String get aiPanelOpenContextPanel;

  /// No description provided for @safetyBannerAddLimit.
  ///
  /// In en, this message translates to:
  /// **'Add LIMIT'**
  String get safetyBannerAddLimit;

  /// No description provided for @safetyBannerCooldown.
  ///
  /// In en, this message translates to:
  /// **'Confirm ({seconds}s)'**
  String safetyBannerCooldown(int seconds);

  /// No description provided for @safetyDmlAllRowsWarning.
  ///
  /// In en, this message translates to:
  /// **'This operation will affect all matching rows. Consider adding a LIMIT clause.'**
  String get safetyDmlAllRowsWarning;

  /// No description provided for @safetySeverityHigh.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get safetySeverityHigh;

  /// No description provided for @safetySeverityMedium.
  ///
  /// In en, this message translates to:
  /// **'Warning'**
  String get safetySeverityMedium;

  /// No description provided for @safetySeverityLow.
  ///
  /// In en, this message translates to:
  /// **'Info'**
  String get safetySeverityLow;

  /// No description provided for @safetySeverityPolicy.
  ///
  /// In en, this message translates to:
  /// **'Policy'**
  String get safetySeverityPolicy;

  /// No description provided for @gateTitleSingle.
  ///
  /// In en, this message translates to:
  /// **'Execution check: {count} risk(s) found in this SQL'**
  String gateTitleSingle(int count);

  /// No description provided for @gateTitleMulti.
  ///
  /// In en, this message translates to:
  /// **'Execution check: {count} risk(s) found across {total} statements'**
  String gateTitleMulti(int count, int total);

  /// No description provided for @gateDdlImpactTitle.
  ///
  /// In en, this message translates to:
  /// **'DDL impact analysis'**
  String get gateDdlImpactTitle;

  /// No description provided for @gateStatementLabel.
  ///
  /// In en, this message translates to:
  /// **'Stmt {n}'**
  String gateStatementLabel(int n);

  /// No description provided for @gateSuggestionLabel.
  ///
  /// In en, this message translates to:
  /// **'Suggested fix'**
  String get gateSuggestionLabel;

  /// No description provided for @gateOverview.
  ///
  /// In en, this message translates to:
  /// **'Statements {total} · High {high} · Warning {medium} · Info {low} · Clean {ok}'**
  String gateOverview(int total, int high, int medium, int low, int ok);

  /// No description provided for @gateSkipHighRisk.
  ///
  /// In en, this message translates to:
  /// **'Skip {skip} high-risk, run {exec}'**
  String gateSkipHighRisk(int skip, int exec);

  /// No description provided for @gateAllHighDisabled.
  ///
  /// In en, this message translates to:
  /// **'All high-risk — nothing to run'**
  String get gateAllHighDisabled;

  /// No description provided for @gateApplySuggestions.
  ///
  /// In en, this message translates to:
  /// **'Apply suggestions'**
  String get gateApplySuggestions;

  /// No description provided for @gateProceed.
  ///
  /// In en, this message translates to:
  /// **'Run anyway'**
  String get gateProceed;

  /// No description provided for @gateProceedAll.
  ///
  /// In en, this message translates to:
  /// **'Run all anyway'**
  String get gateProceedAll;

  /// No description provided for @gateCancelAll.
  ///
  /// In en, this message translates to:
  /// **'Cancel all'**
  String get gateCancelAll;

  /// No description provided for @settingsNavAppearance.
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsNavAppearance;

  /// No description provided for @settingsNavAi.
  ///
  /// In en, this message translates to:
  /// **'AI'**
  String get settingsNavAi;

  /// No description provided for @settingsNavQuery.
  ///
  /// In en, this message translates to:
  /// **'Query'**
  String get settingsNavQuery;

  /// No description provided for @settingsNavLanguage.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsNavLanguage;

  /// No description provided for @settingsNavSecurity.
  ///
  /// In en, this message translates to:
  /// **'Security'**
  String get settingsNavSecurity;

  /// No description provided for @settingsNavAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsNavAbout;

  /// No description provided for @piiExportStepFormat.
  ///
  /// In en, this message translates to:
  /// **'Format'**
  String get piiExportStepFormat;

  /// No description provided for @piiExportStepScan.
  ///
  /// In en, this message translates to:
  /// **'PII Scan'**
  String get piiExportStepScan;

  /// No description provided for @piiExportStepConfirm.
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get piiExportStepConfirm;

  /// No description provided for @piiExportNoPiiTitle.
  ///
  /// In en, this message translates to:
  /// **'No PII detected'**
  String get piiExportNoPiiTitle;

  /// No description provided for @piiExportNoPiiSubtitle.
  ///
  /// In en, this message translates to:
  /// **'All columns will be exported as-is'**
  String get piiExportNoPiiSubtitle;

  /// No description provided for @piiExportDetectedCount.
  ///
  /// In en, this message translates to:
  /// **'{count} columns contain PII'**
  String piiExportDetectedCount(int count);

  /// No description provided for @piiExportHighSensitivity.
  ///
  /// In en, this message translates to:
  /// **'(high sensitivity)'**
  String get piiExportHighSensitivity;

  /// No description provided for @piiExportKeep.
  ///
  /// In en, this message translates to:
  /// **'Keep'**
  String get piiExportKeep;

  /// No description provided for @piiExportMask.
  ///
  /// In en, this message translates to:
  /// **'Mask'**
  String get piiExportMask;

  /// No description provided for @piiExportHash.
  ///
  /// In en, this message translates to:
  /// **'Hash'**
  String get piiExportHash;

  /// No description provided for @piiExportDrop.
  ///
  /// In en, this message translates to:
  /// **'Drop column'**
  String get piiExportDrop;

  /// No description provided for @piiExportReadyTitle.
  ///
  /// In en, this message translates to:
  /// **'Ready to export'**
  String get piiExportReadyTitle;

  /// No description provided for @piiExportSummaryFormat.
  ///
  /// In en, this message translates to:
  /// **'Format'**
  String get piiExportSummaryFormat;

  /// No description provided for @piiExportSummaryRows.
  ///
  /// In en, this message translates to:
  /// **'Rows'**
  String get piiExportSummaryRows;

  /// No description provided for @piiExportSummaryPiiColumns.
  ///
  /// In en, this message translates to:
  /// **'PII columns handled'**
  String get piiExportSummaryPiiColumns;

  /// No description provided for @piiExportFootnote.
  ///
  /// In en, this message translates to:
  /// **'PII columns follow the chosen actions; non-PII columns export as-is'**
  String get piiExportFootnote;

  /// No description provided for @serverBarNotConnected.
  ///
  /// In en, this message translates to:
  /// **'Not connected'**
  String get serverBarNotConnected;

  /// No description provided for @serverBarConnecting.
  ///
  /// In en, this message translates to:
  /// **'Connecting…'**
  String get serverBarConnecting;

  /// No description provided for @serverBarLocal.
  ///
  /// In en, this message translates to:
  /// **'Local'**
  String get serverBarLocal;

  /// No description provided for @serverBarConnected.
  ///
  /// In en, this message translates to:
  /// **'Connected'**
  String get serverBarConnected;

  /// No description provided for @serverBarReconnecting.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting…'**
  String get serverBarReconnecting;

  /// No description provided for @serverBarReconnectingIn.
  ///
  /// In en, this message translates to:
  /// **'Reconnecting in {seconds}s…'**
  String serverBarReconnectingIn(int seconds);

  /// No description provided for @serverBarServerUrl.
  ///
  /// In en, this message translates to:
  /// **'Server: {url}'**
  String serverBarServerUrl(String url);

  /// No description provided for @serverBarDisconnect.
  ///
  /// In en, this message translates to:
  /// **'Disconnect'**
  String get serverBarDisconnect;

  /// No description provided for @serverBarUnknownUser.
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get serverBarUnknownUser;

  /// No description provided for @serverConnectUnexpectedError.
  ///
  /// In en, this message translates to:
  /// **'An unexpected error occurred.'**
  String get serverConnectUnexpectedError;

  /// No description provided for @cellViewerCopy.
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get cellViewerCopy;

  /// No description provided for @cellViewerChars.
  ///
  /// In en, this message translates to:
  /// **'{count} characters'**
  String cellViewerChars(Object count);

  /// No description provided for @slowQueryMenuLabel.
  ///
  /// In en, this message translates to:
  /// **'Slow Query Stats'**
  String get slowQueryMenuLabel;

  /// No description provided for @slowQueryDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Slow Query Stats'**
  String get slowQueryDialogTitle;

  /// No description provided for @slowQueryScopeBanner.
  ///
  /// In en, this message translates to:
  /// **'Queries run through dbmaster/server slower than {thresholdMs} ms are recorded; when native slow-log collection is enabled on the instance, the database\'s own slow queries are included too (distinguished by source).'**
  String slowQueryScopeBanner(int thresholdMs);

  /// No description provided for @slowQueryWindow1h.
  ///
  /// In en, this message translates to:
  /// **'Last hour'**
  String get slowQueryWindow1h;

  /// No description provided for @slowQueryWindow24h.
  ///
  /// In en, this message translates to:
  /// **'Last 24 hours'**
  String get slowQueryWindow24h;

  /// No description provided for @slowQueryWindow7d.
  ///
  /// In en, this message translates to:
  /// **'Last 7 days'**
  String get slowQueryWindow7d;

  /// No description provided for @slowQuerySortTotalMs.
  ///
  /// In en, this message translates to:
  /// **'Total time'**
  String get slowQuerySortTotalMs;

  /// No description provided for @slowQuerySortCount.
  ///
  /// In en, this message translates to:
  /// **'Count'**
  String get slowQuerySortCount;

  /// No description provided for @slowQuerySortAvgMs.
  ///
  /// In en, this message translates to:
  /// **'Avg time'**
  String get slowQuerySortAvgMs;

  /// No description provided for @slowQuerySortMaxMs.
  ///
  /// In en, this message translates to:
  /// **'Max time'**
  String get slowQuerySortMaxMs;

  /// No description provided for @slowQueryAllConnections.
  ///
  /// In en, this message translates to:
  /// **'All connections'**
  String get slowQueryAllConnections;

  /// No description provided for @slowQueryDigestStats.
  ///
  /// In en, this message translates to:
  /// **'{count} calls · total {total} · avg {avg} · max {max}'**
  String slowQueryDigestStats(int count, String total, String avg, String max);

  /// No description provided for @slowQueryLastSeen.
  ///
  /// In en, this message translates to:
  /// **'last seen {time}'**
  String slowQueryLastSeen(String time);

  /// No description provided for @slowQueryEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No slow queries'**
  String get slowQueryEmptyTitle;

  /// No description provided for @slowQueryEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Nothing above the sampling threshold in this window. Run something slow through dbmaster and come back.'**
  String get slowQueryEmptyBody;

  /// No description provided for @slowQueryLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load slow query stats.'**
  String get slowQueryLoadFailed;

  /// No description provided for @slowQueryRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get slowQueryRetry;

  /// No description provided for @slowQueryLoadMore.
  ///
  /// In en, this message translates to:
  /// **'Show more ({shown} of {total})'**
  String slowQueryLoadMore(int shown, int total);

  /// No description provided for @slowQueryStatusOk.
  ///
  /// In en, this message translates to:
  /// **'ok'**
  String get slowQueryStatusOk;

  /// No description provided for @slowQueryStatusError.
  ///
  /// In en, this message translates to:
  /// **'error'**
  String get slowQueryStatusError;

  /// No description provided for @slowQueryStatusCancelled.
  ///
  /// In en, this message translates to:
  /// **'cancelled'**
  String get slowQueryStatusCancelled;

  /// No description provided for @slowQueryDatabaseLabel.
  ///
  /// In en, this message translates to:
  /// **'Database'**
  String get slowQueryDatabaseLabel;

  /// No description provided for @slowQueryNoPlaintext.
  ///
  /// In en, this message translates to:
  /// **'Plaintext SQL is disabled on this instance (digest only).'**
  String get slowQueryNoPlaintext;

  /// No description provided for @slowQueryCopySql.
  ///
  /// In en, this message translates to:
  /// **'Copy SQL'**
  String get slowQueryCopySql;

  /// No description provided for @slowQueryCopied.
  ///
  /// In en, this message translates to:
  /// **'Copied'**
  String get slowQueryCopied;

  /// No description provided for @reportsMenuLabel.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get reportsMenuLabel;

  /// No description provided for @reportsDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Reports'**
  String get reportsDialogTitle;

  /// No description provided for @reportsGenerateButton.
  ///
  /// In en, this message translates to:
  /// **'Generate weekly report'**
  String get reportsGenerateButton;

  /// No description provided for @reportsGeneratedToast.
  ///
  /// In en, this message translates to:
  /// **'Weekly report generated.'**
  String get reportsGeneratedToast;

  /// No description provided for @reportsExistingToast.
  ///
  /// In en, this message translates to:
  /// **'This week\'s report already exists.'**
  String get reportsExistingToast;

  /// No description provided for @reportsEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'No reports'**
  String get reportsEmptyTitle;

  /// No description provided for @reportsEmptyBody.
  ///
  /// In en, this message translates to:
  /// **'Generate this week\'s slow-query report, or wait for the weekly schedule.'**
  String get reportsEmptyBody;

  /// No description provided for @reportsLoadFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to load reports.'**
  String get reportsLoadFailed;

  /// No description provided for @reportsRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get reportsRetry;

  /// No description provided for @reportsLoadMore.
  ///
  /// In en, this message translates to:
  /// **'Show more ({shown} of {total})'**
  String reportsLoadMore(int shown, int total);

  /// No description provided for @reportsWindowLabel.
  ///
  /// In en, this message translates to:
  /// **'Window'**
  String get reportsWindowLabel;

  /// No description provided for @reportsTruncatedHint.
  ///
  /// In en, this message translates to:
  /// **'Partial window: older samples were already rotated out by retention.'**
  String get reportsTruncatedHint;

  /// No description provided for @reportsSamplesLabel.
  ///
  /// In en, this message translates to:
  /// **'Samples'**
  String get reportsSamplesLabel;

  /// No description provided for @reportsDistinctLabel.
  ///
  /// In en, this message translates to:
  /// **'Distinct queries'**
  String get reportsDistinctLabel;

  /// No description provided for @reportsTotalTimeLabel.
  ///
  /// In en, this message translates to:
  /// **'Total time'**
  String get reportsTotalTimeLabel;

  /// No description provided for @reportsErrorsLabel.
  ///
  /// In en, this message translates to:
  /// **'Errors'**
  String get reportsErrorsLabel;

  /// No description provided for @reportsWowLabel.
  ///
  /// In en, this message translates to:
  /// **'vs last week'**
  String get reportsWowLabel;

  /// No description provided for @reportsTopSection.
  ///
  /// In en, this message translates to:
  /// **'Top queries'**
  String get reportsTopSection;

  /// No description provided for @reportsByDaySection.
  ///
  /// In en, this message translates to:
  /// **'By day'**
  String get reportsByDaySection;

  /// No description provided for @reportsByConnectionSection.
  ///
  /// In en, this message translates to:
  /// **'By connection'**
  String get reportsByConnectionSection;

  /// No description provided for @reportsUnknownType.
  ///
  /// In en, this message translates to:
  /// **'Unknown report type — raw content:'**
  String get reportsUnknownType;

  /// No description provided for @reportsAnalyzeWithAi.
  ///
  /// In en, this message translates to:
  /// **'Analyze with AI'**
  String get reportsAnalyzeWithAi;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['de', 'en', 'fr', 'ru', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when language+country codes are specified.
  switch (locale.languageCode) {
    case 'zh':
      {
        switch (locale.countryCode) {
          case 'TW':
            return AppLocalizationsZhTw();
        }
        break;
      }
  }

  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'de':
      return AppLocalizationsDe();
    case 'en':
      return AppLocalizationsEn();
    case 'fr':
      return AppLocalizationsFr();
    case 'ru':
      return AppLocalizationsRu();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
