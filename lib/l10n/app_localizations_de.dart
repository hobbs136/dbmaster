// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get filterBarApply => 'Anwenden';

  @override
  String get filterBarAddCondition => 'Bedingung hinzufügen';

  @override
  String get filterBarAnd => 'UND';

  @override
  String get filterBarOr => 'ODER';

  @override
  String get filterBarNoColumns => 'Keine Spalten';

  @override
  String get filterBarLoading => 'Laden…';

  @override
  String get mongoAutocompleteTitle => 'Mongo-Autovervollständigung';

  @override
  String get appTitle => 'DbMaster';

  @override
  String get settingsTitle => 'Einstellungen';

  @override
  String get settingsLanguage => 'Sprache';

  @override
  String get settingsTheme => 'Thema';

  @override
  String get settingsGeneral => 'Allgemein';

  @override
  String get settingsConnection => 'Verbindung';

  @override
  String get settingsEditor => 'Editor';

  @override
  String get settingsAbout => 'Über';

  @override
  String get connectionNewConnection => 'Neue Verbindung';

  @override
  String get connectionEditConnection => 'Verbindung bearbeiten';

  @override
  String get connectionManageConnection => 'Verbindung verwalten';

  @override
  String get connectionDeleteConnection => 'Verbindung löschen';

  @override
  String get connectionConnect => 'Verbinden';

  @override
  String get connectionCreateDatabase => 'Datenbank erstellen';

  @override
  String get connectionEnableReadOnly => 'Schreibschutz aktivieren';

  @override
  String get connectionDisableReadOnly => 'Schreibschutz deaktivieren';

  @override
  String connectionMoveToGroup(String groupName) {
    return 'Nach $groupName verschieben';
  }

  @override
  String get connectionRemoveFromGroup => 'Aus Gruppe entfernen';

  @override
  String get connectionCollapseAll => 'Alle einklappen';

  @override
  String get connectionDisconnect => 'Trennen';

  @override
  String get connectionTestConnection => 'Verbindung testen';

  @override
  String get connectionConnectionName => 'Verbindungsname';

  @override
  String get connectionHost => 'Host';

  @override
  String get connectionPort => 'Port';

  @override
  String get connectionUsername => 'Benutzername';

  @override
  String get connectionPassword => 'Passwort';

  @override
  String get connectionDatabase => 'Datenbank';

  @override
  String get connectionEnvironment => 'Umgebung';

  @override
  String get connectionEnvironmentNone => 'Keine';

  @override
  String get commonSave => 'Speichern';

  @override
  String get commonCancel => 'Abbrechen';

  @override
  String get commonDelete => 'Löschen';

  @override
  String get commonEdit => 'Bearbeiten';

  @override
  String get commonAdd => 'Hinzufügen';

  @override
  String get commonClose => 'Schließen';

  @override
  String get commonDone => 'Done';

  @override
  String get commonSelect => 'Select';

  @override
  String get commonConfirm => 'Bestätigen';

  @override
  String get commonSearch => 'Suchen';

  @override
  String get commonRefresh => 'Aktualisieren';

  @override
  String get commonLoading => 'Laden...';

  @override
  String get commonNoData => 'Keine Daten';

  @override
  String get commonSuccess => 'Erfolg';

  @override
  String get commonError => 'Fehler';

  @override
  String get commonWarning => 'Warnung';

  @override
  String get tableNewTable => 'Neue Tabelle';

  @override
  String get tableEditTable => 'Tabelle bearbeiten';

  @override
  String get tableDeleteTable => 'Tabelle löschen';

  @override
  String get tableTableName => 'Tabellenname';

  @override
  String get tableColumns => 'Spalten';

  @override
  String get tableIndexes => 'Indizes';

  @override
  String get tablePrimaryKey => 'Primärschlüssel';

  @override
  String get tableForeignKey => 'Fremdschlüssel';

  @override
  String get tableRenameTable => 'Tabelle umbenennen';

  @override
  String get tableNewTableName => 'Neuer Tabellenname';

  @override
  String get queryExecute => 'Ausführen';

  @override
  String get queryExecuteSelected => 'Ausgewählte ausführen';

  @override
  String get queryFormat => 'Formatieren';

  @override
  String get queryClear => 'Löschen';

  @override
  String get queryHistory => 'Verlauf';

  @override
  String get queryResults => 'Ergebnisse';

  @override
  String get sidebarConnections => 'Verbindungen';

  @override
  String get sidebarDatabases => 'Datenbanken';

  @override
  String get sidebarTables => 'Tabellen';

  @override
  String get sidebarKeys => 'Schlüssel';

  @override
  String get sidebarCollections => 'Sammlungen';

  @override
  String get sidebarSuperTables => 'Super-Tabellen';

  @override
  String get sidebarViews => 'Ansichten';

  @override
  String get sidebarSavedQueries => 'Gespeicherte Abfragen';

  @override
  String get sidebarProcedures => 'Gespeicherte Prozeduren';

  @override
  String get sidebarTriggers => 'Trigger';

  @override
  String get sidebarFunctions => 'Funktionen';

  @override
  String get sidebarServer => 'Server';

  @override
  String get sidebarProcessList => 'Prozessliste';

  @override
  String get sidebarServerStatus => 'Serverstatus';

  @override
  String get sidebarNoUsers => 'Keine Benutzer';

  @override
  String get sidebarNoActiveProcesses => 'Keine aktiven Prozesse';

  @override
  String sidebarTdColsTags(int cols, int tags) {
    return '$cols Spalten, $tags Tags';
  }

  @override
  String sidebarTdColumnsCount(int count) {
    return 'Spalten ($count)';
  }

  @override
  String sidebarTdTagsCount(int count) {
    return 'Tags ($count)';
  }

  @override
  String get sidebarTdDeleteTitle => 'SuperTable löschen';

  @override
  String sidebarTdDeleteConfirm(String name) {
    return 'SuperTable „$name“ wirklich löschen?\n\nAlle zugehörigen SubTables werden ebenfalls gelöscht!';
  }

  @override
  String get sidebarDeleteGroup => 'Gruppe löschen';

  @override
  String get sidebarDeleteGroupPrompt => 'Zu löschende Gruppe auswählen:';

  @override
  String get sidebarConnectionSwitch => 'Verbindung wechseln';

  @override
  String get sidebarSelectConnectionHint =>
      'Verbindung oben im Auswahlfeld wählen, um zu beginnen';

  @override
  String get sidebarConnectionNone => 'Keine Verbindung';

  @override
  String get sidebarManageConnections => 'Verbindungen verwalten…';

  @override
  String get sidebarExtensions => 'Extensions';

  @override
  String get noExtensionsInstalled => 'No extensions installed';

  @override
  String get sidebarSchemas => 'Schemas';

  @override
  String get sidebarMaterializedViews => 'Materialisierte Ansichten';

  @override
  String get sidebarSequences => 'Sequenzen';

  @override
  String get settingsGeneralSettings => 'Allgemeine Einstellungen';

  @override
  String get settingsAppearanceSettings => 'Darstellung';

  @override
  String get settingsEditorSettings => 'Editor-Einstellungen';

  @override
  String get settingsEnableAutocomplete => 'Autovervollständigung aktivieren';

  @override
  String get settingsAutocompleteDescription =>
      'SQL-Schlüsselwörter und Tabellennamen automatisch vorschlagen';

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
  String get settingsAiSettings => 'KI-Einstellungen';

  @override
  String get settingsAutoExecuteSql => 'SQL automatisch ausführen';

  @override
  String get settingsAutoExecuteSqlDescription =>
      'SQL automatisch ausführen, wenn ein Tab geöffnet wird';

  @override
  String get settingsThemeSettings => 'Design';

  @override
  String get settingsDarkMode => 'Dunkel';

  @override
  String get settingsLightMode => 'Hell';

  @override
  String get shortcutCategoryFile => 'Datei';

  @override
  String get shortcutCategoryEdit => 'Bearbeiten';

  @override
  String get shortcutCategoryView => 'Ansicht';

  @override
  String get shortcutCategoryAi => 'KI';

  @override
  String get shortcutCategoryTab => 'Tabs';

  @override
  String get shortcutNewConnection => 'Neue Verbindung';

  @override
  String get shortcutNewTab => 'Neuer Tab';

  @override
  String get shortcutCloseTab => 'Tab schließen';

  @override
  String get shortcutSaveQuery => 'Abfrage speichern';

  @override
  String get shortcutExportData => 'Daten exportieren';

  @override
  String get shortcutExecuteQuery => 'Abfrage ausführen';

  @override
  String get shortcutExecuteQueryNewTab => 'Abfrage in neuem Tab ausführen';

  @override
  String get shortcutFormatSql => 'SQL formatieren';

  @override
  String get shortcutFind => 'Suchen';

  @override
  String get shortcutReplace => 'Ersetzen';

  @override
  String get shortcutAutocomplete => 'Autovervollständigung';

  @override
  String get shortcutUndo => 'Rückgängig';

  @override
  String get shortcutRedo => 'Wiederholen';

  @override
  String get shortcutToggleSidebar => 'Seitenleiste umschalten';

  @override
  String get shortcutToggleAiPanel => 'KI-Panel umschalten';

  @override
  String get shortcutCommandPalette => 'Befehlspalette';

  @override
  String get shortcutShortcutHelp => 'Tastenkürzel';

  @override
  String get shortcutGenerateSql => 'SQL generieren';

  @override
  String get shortcutOptimizeSql => 'SQL optimieren';

  @override
  String get shortcutExplainSql => 'SQL erklären';

  @override
  String get shortcutNextTab => 'Nächster Tab';

  @override
  String get shortcutPreviousTab => 'Vorheriger Tab';

  @override
  String get shortcutSwitchToTab => 'Zu Tab wechseln';

  @override
  String get shortcutToggleAiFullscreen => 'KI-Panel Vollbild';

  @override
  String get shortcutAuditLog => 'Abfrage-Audit-Protokoll';

  @override
  String get shortcutIncreaseOpacity => 'Overlay-Deckkraft erhöhen';

  @override
  String get shortcutDecreaseOpacity => 'Overlay-Deckkraft verringern';

  @override
  String get tableCreateNewTable => 'Neue Tabelle erstellen';

  @override
  String get toolbarBackup => 'Sicherung';

  @override
  String get toolbarImport => 'Importieren';

  @override
  String get toolbarExport => 'Exportieren';

  @override
  String get sidebarExpand => 'Seitenleiste erweitern';

  @override
  String get sidebarSettings => 'Einstellungen';

  @override
  String get sidebarSearchHint =>
      'Suche nach Verbindungen, Tabellen, Ansichten...';

  @override
  String sidebarConnectionActive(Object count) {
    return '$count aktive Verbindungen';
  }

  @override
  String get sidebarNoConnections => 'Keine gespeicherten Verbindungen';

  @override
  String get sidebarClickToCreateConnection =>
      'Klicken Sie auf die Schaltfläche unten, um eine neue Verbindung zu erstellen';

  @override
  String get sidebarCreateConnection => 'Neue Verbindung';

  @override
  String get resultsExport => 'Exportieren';

  @override
  String get resultsSave => 'Speichern';

  @override
  String get resultsDiscard => 'Verwerfen';

  @override
  String get resultsNoDataToExport => 'Keine Daten zum Exportieren';

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
  String get resultsConfirmDiscardChanges => 'Änderungen verwerfen bestätigen';

  @override
  String resultsDiscardChangesMessage(Object count) {
    return 'Möchten Sie wirklich $count Änderungen verwerfen? Diese Aktion kann nicht rückgängig gemacht werden.';
  }

  @override
  String get resultsContinueEditing => 'Weiter bearbeiten';

  @override
  String get resultsDiscardChanges => 'Änderungen verwerfen';

  @override
  String get resultsConfirmExecuteSQL => 'SQL-Ausführung bestätigen';

  @override
  String get resultsBarChart => 'Balkendiagramm';

  @override
  String get resultsLineChart => 'Liniendiagramm';

  @override
  String get resultsPieChart => 'Kreisdiagramm';

  @override
  String get resultsSelectAxisFields => 'Bitte X- und Y-Achsenfelder auswählen';

  @override
  String get statusNotConnected => 'Nicht verbunden';

  @override
  String get statusConnected => 'Verbunden';

  @override
  String statusTables(Object count) {
    return '$count Tabellen';
  }

  @override
  String get statusNone => 'Keine';

  @override
  String statusVersion(Object version) {
    return 'v$version';
  }

  @override
  String get backupManagement => 'Sicherungsverwaltung';

  @override
  String get backupList => 'Sicherungsliste';

  @override
  String get createBackup => 'Sicherung erstellen';

  @override
  String get noBackupFiles => 'Keine Sicherungsdateien';

  @override
  String get clickCreateBackupTab =>
      'Klicken Sie auf die Registerkarte \'Sicherung erstellen\', um zu beginnen';

  @override
  String get importBackup => 'Sicherung importieren';

  @override
  String get previewContent => 'Inhalt anzeigen';

  @override
  String get exportFile => 'Datei exportieren';

  @override
  String get restoreBackup => 'Sicherung wiederherstellen';

  @override
  String get selectBackupToView =>
      'Wählen Sie eine Sicherung aus, um Details anzuzeigen';

  @override
  String get database => 'Datenbank';

  @override
  String get backupType => 'Typ';

  @override
  String get backupSize => 'Größe';

  @override
  String get createdAt => 'Erstellungszeit';

  @override
  String get tableCount => 'Tabellenanzahl';

  @override
  String get description => 'Beschreibung';

  @override
  String get preview => 'Vorschau';

  @override
  String get export => 'Exportieren';

  @override
  String get restore => 'Wiederherstellen';

  @override
  String get confirmRestore => 'Wiederherstellung bestätigen';

  @override
  String confirmRestoreMessage(Object name) {
    return 'Möchten Sie wirklich die Sicherung \"$name\" wiederherstellen?\n\nDadurch werden alle SQL-Anweisungen in der Sicherungsdatei ausgeführt, was möglicherweise bestehende Daten überschreibt.';
  }

  @override
  String get confirmDelete => 'Löschen bestätigen';

  @override
  String confirmDeleteMessage(Object name) {
    return 'Möchten Sie wirklich die Sicherung \"$name\" löschen?\n\nDiese Aktion kann nicht rückgängig gemacht werden.';
  }

  @override
  String get backupFormat => 'Sicherungsformat';

  @override
  String get backupContent => 'Sicherungsinhalt';

  @override
  String get selectTablesHint => 'Tabellen auswählen (leer lassen für alle)';

  @override
  String get advancedOptions => 'Erweiterte Optionen';

  @override
  String get includeStructure => 'Tabellenstruktur einbeziehen';

  @override
  String get includeStructureDesc => 'CREATE TABLE-Anweisungen';

  @override
  String get includeData => 'Daten einbeziehen';

  @override
  String get includeDataDesc => 'INSERT-Anweisungen oder Datenzeilen';

  @override
  String get noTablesAvailable => 'Keine Tabellen verfügbar';

  @override
  String get selectAll => 'Alle auswählen';

  @override
  String get deselectAll => 'Alle abwählen';

  @override
  String tablesSelected(Object count) {
    return '$count Tabellen ausgewählt';
  }

  @override
  String get addDropTable => 'DROP TABLE hinzufügen';

  @override
  String get useExtendedInsert => 'Erweitertes INSERT verwenden';

  @override
  String get useExtendedInsertDesc =>
      'Mehrere Zeilen zu einem INSERT zusammenführen';

  @override
  String get rowLimitPerTable => 'Zeilenlimit pro Tabelle (optional)';

  @override
  String get leaveEmptyForNoLimit => 'Leer lassen für kein Limit';

  @override
  String get whereCondition => 'WHERE-Bedingung (optional)';

  @override
  String get whereConditionExample => 'z.B.: id > 100';

  @override
  String get enterBackupDescription =>
      'Sicherungsbeschreibung eingeben (optional)';

  @override
  String get startBackup => 'Sicherung starten';

  @override
  String get backupProgress => 'Sicherungsfortschritt';

  @override
  String get waitingToStartBackup => 'Warten auf Sicherungsstart...';

  @override
  String get currentTable => 'Aktuelle Tabelle';

  @override
  String get progressPercent => 'Fortschritt';

  @override
  String get backupComplete => 'Sicherung abgeschlossen!';

  @override
  String get backupFailed => 'Sicherung fehlgeschlagen';

  @override
  String get loadBackupListFailed => 'Sicherungsliste laden fehlgeschlagen';

  @override
  String get retry => 'Wiederholen';

  @override
  String get previewFailed => 'Vorschau fehlgeschlagen';

  @override
  String get exportedTo => 'Exportiert nach';

  @override
  String get backupRestoreSuccess => 'Sicherung erfolgreich wiederhergestellt';

  @override
  String get restoreFailed => 'Wiederherstellung fehlgeschlagen';

  @override
  String get backupDeleted => 'Sicherung gelöscht';

  @override
  String deleteFailed(Object error) {
    return 'Löschen fehlgeschlagen: $error';
  }

  @override
  String get selectBackupFile => 'Sicherungsdatei auswählen';

  @override
  String get backupImportSuccess => 'Sicherungsdatei erfolgreich importiert';

  @override
  String importFailed(String error) {
    return 'Import fehlgeschlagen: $error';
  }

  @override
  String get selectAtLeastOneOption =>
      'Bitte wählen Sie mindestens Sicherungsstruktur oder Daten aus';

  @override
  String get backupFailedError => 'Sicherung fehlgeschlagen';

  @override
  String get aiAssistant => 'KI-Assistent';

  @override
  String get aiAnalyze => 'KI-Analyse';

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
  String get apiSettings => 'API-Einstellungen';

  @override
  String get clearChat => 'Chat löschen';

  @override
  String get model => 'Modell';

  @override
  String get enterModelName => 'Modellname eingeben';

  @override
  String get autoExecuteSql => 'SQL automatisch ausführen';

  @override
  String get autoExecuteSqlDesc =>
      'Wenn aktiviert, werden KI-generierte Abfragen automatisch ausgeführt';

  @override
  String get aiDatabaseAssistant => 'KI-Datenbankassistent';

  @override
  String get aiAssistantDesc =>
      'Unterstützt mehrere große Modellanbieter\nHilft beim Schreiben von SQL, Optimieren von Abfragen, Erklären der Datenbankstruktur';

  @override
  String get enterYourQuestion => 'Geben Sie Ihre Frage ein...';

  @override
  String configureApiKeyFirst(Object provider) {
    return 'Bitte konfigurieren Sie zuerst den API-Schlüssel für $provider in den Einstellungen, um die KI-Konversationsfunktion zu aktivieren.\n\nKlicken Sie auf das Einstellungssymbol oben rechts, um zu konfigurieren.';
  }

  @override
  String get generationFailed => 'Generierung fehlgeschlagen';

  @override
  String get stepAnalyzeNeeds =>
      'Schritt 1: Benutzeranforderungen analysieren, zu suchende Tabellen bestimmen...';

  @override
  String get stepGetTableSchema =>
      'Schritt 2: Detaillierte CREATE TABLE-Anweisungen der Tabellen abrufen...';

  @override
  String get stepGenerateSql => 'Schritt 3: SQL-Anweisungen generieren...';

  @override
  String get analysisResultTables => 'Analyseergebnis: Zu suchende Tabellen';

  @override
  String get tableSchemaInfo => 'Tabellenschema-Informationen';

  @override
  String get operationCancelled => 'Operation abgebrochen';

  @override
  String get executingSql => 'SQL wird ausgeführt...';

  @override
  String executeSuccessRows(Object count) {
    return 'Ausführung erfolgreich, $count Datenzeilen zurückgegeben';
  }

  @override
  String get executeFailedError => 'Ausführung fehlgeschlagen';

  @override
  String get confirmDangerousOperation => 'Gefährliche Operation bestätigen?';

  @override
  String get confirmExecuteSql => 'SQL-Ausführung bestätigen';

  @override
  String get dangerousOperationWarning =>
      'Diese Operation könnte Daten ändern oder löschen, bitte mit Vorsicht ausführen!';

  @override
  String get sqlCopied => 'SQL kopiert';

  @override
  String get sqlGenerationComplete => 'SQL-Generierung abgeschlossen';

  @override
  String get dangerousOperation => 'Gefährliche Operation';

  @override
  String get dangerousOperationDesc =>
      'Dies ist eine gefährliche Operation, bitte mit Vorsicht behandeln';

  @override
  String get taskCompleteDesc =>
      'Aufgabe abgeschlossen, Sie können SQL ausführen oder kopieren';

  @override
  String get generatedSql => 'Generiertes SQL';

  @override
  String get dangerous => 'Gefährlich';

  @override
  String get confirmExecute => 'Ausführung bestätigen';

  @override
  String get requestTimeout => 'Anforderungszeitlimit';

  @override
  String get seconds => 'Sekunden';

  @override
  String get apiSettingsSaved => 'API-Einstellungen gespeichert';

  @override
  String get dataImport => 'Datenimport';

  @override
  String get selectFile => 'Datei auswählen';

  @override
  String get noFileSelected => 'Keine Datei ausgewählt';

  @override
  String get importConfig => 'Importkonfiguration';

  @override
  String get targetTableName => 'Zieltabellenname';

  @override
  String get enterTableName => 'Tabellennamen eingeben';

  @override
  String get includeHeader => 'Kopfzeile einbeziehen';

  @override
  String get delimiter => 'Trennzeichen';

  @override
  String get overwriteTable => 'Tabelle überschreiben';

  @override
  String get deleteExistingTable => '(Bestehende Tabelle löschen)';

  @override
  String get batchSize => 'Batch-Größe';

  @override
  String dataPreviewRows(Object count) {
    return 'Datenvorschau ($count Zeilen)';
  }

  @override
  String get pleaseSelectFile =>
      'Bitte wählen Sie eine Datei aus, um Daten anzuzeigen';

  @override
  String get importProgress => 'Importfortschritt';

  @override
  String get importPreparing => 'Importvorbereitung...';

  @override
  String get totalRecords => 'Gesamt';

  @override
  String get importedRecords => 'Importiert';

  @override
  String get failedRecords => 'Fehlgeschlagen';

  @override
  String get readyToImport => 'Bereit zum Importieren';

  @override
  String get importingData => 'Daten werden importiert...';

  @override
  String get importComplete => 'Import abgeschlossen!';

  @override
  String get parseFileFailed => 'Dateiparsen fehlgeschlagen';

  @override
  String get noDataToImport => 'Keine Daten zum Importieren';

  @override
  String get selectDatabaseFirst =>
      'Bitte wählen Sie zuerst eine Datenbank aus';

  @override
  String get importFailedError => 'Import fehlgeschlagen';

  @override
  String get startImport => 'Import starten';

  @override
  String get importing => 'Importieren...';

  @override
  String get optimizeSql => 'SQL optimieren';

  @override
  String get explainQuery => 'Abfrage erklären';

  @override
  String get generateInsert => 'INSERT generieren';

  @override
  String get generateUpdate => 'UPDATE generieren';

  @override
  String get generateDelete => 'DELETE generieren';

  @override
  String get createTableStatement => 'CREATE TABLE-Anweisung';

  @override
  String get securityCheck => 'Sicherheitsprüfung';

  @override
  String get indexSuggestion => 'Indexvorschlag';

  @override
  String get executionPlan => 'Ausführungsplan';

  @override
  String get pleaseEnterSql => 'Bitte geben Sie zuerst eine SQL-Anweisung ein';

  @override
  String get pleaseConnectDatabase =>
      'Bitte verbinden Sie zuerst eine Datenbank';

  @override
  String get analysisFailed => 'Analyse fehlgeschlagen';

  @override
  String get loadHistoryFailed => 'Verlauf laden fehlgeschlagen';

  @override
  String get noQueryHistory =>
      'Keine Abfragehistorie\n\nNach der Ausführung einer SQL-Abfrage wird der Verlauf hier gespeichert.';

  @override
  String queryHistoryRecords(Object count) {
    return 'Abfrageverlauf (letzte $count Einträge)';
  }

  @override
  String get databaseType => 'Datenbanktyp';

  @override
  String get server => 'Server';

  @override
  String get currentDatabase => 'Aktuelle Datenbank';

  @override
  String get notConnected => 'Nicht verbunden';

  @override
  String get notSelected => 'Nicht ausgewählt';

  @override
  String get tableName => 'Tabellenname';

  @override
  String get tableStructureInfo => 'Tabellenstrukturinformationen';

  @override
  String get createStatement => 'CREATE-Anweisung';

  @override
  String andMoreTables(Object count) {
    return '... und $count weitere Tabellen';
  }

  @override
  String get primaryKey => 'Primärschlüssel';

  @override
  String get executionTime => 'Ausführungszeit';

  @override
  String get status => 'Status';

  @override
  String get commonFailed => 'Fehlgeschlagen';

  @override
  String get format => 'Format';

  @override
  String get connectionDefaultDatabase => 'Standarddatenbank';

  @override
  String get connectionSavePassword => 'Passwort speichern';

  @override
  String get connectionAdvancedOptions => 'Erweiterte Optionen';

  @override
  String get connectionTimeout => 'Timeout (Sekunden)';

  @override
  String get connectionUseSSL => 'SSL/TLS verwenden';

  @override
  String get connectionEnableSecureConnection =>
      'Sichere Verbindung aktivieren';

  @override
  String get connectionUseTls => 'TLS/SSL verwenden';

  @override
  String get connectionUseTlsDesc =>
      'Verbindung per TLS verschlüsseln (serverseitig aufgebaut)';

  @override
  String get connectionTlsInsecure =>
      'Zertifikatsprüfung überspringen (unsicher)';

  @override
  String get connectionTlsInsecureDesc =>
      'Serverzertifikat nicht prüfen – nur für vertrauenswürdige/Test-Umgebungen';

  @override
  String get connectionSshSubtitleGateway =>
      'SSH-Tunnel wird vom dbmaster-Server aufgebaut (Konfiguration wird mit der Verbindung übertragen)';

  @override
  String get connectionAutoReconnect => 'Automatische Wiederverbindung';

  @override
  String get connectionAutoReconnectDesc =>
      'Automatisch versuchen, die Verbindung wiederherzustellen, wenn sie unterbrochen wird';

  @override
  String get connectionCharset => 'Zeichensatz';

  @override
  String get connectionTimezone => 'Zeitzone';

  @override
  String get connectionTestSuccess => 'Verbindung erfolgreich!';

  @override
  String connectionTestFailed(String error) {
    return 'Verbindung fehlgeschlagen';
  }

  @override
  String get connectionDatabaseType => 'Datenbanktyp';

  @override
  String get connectionManager => 'Verbindungsmanager';

  @override
  String get connectionSavedConnections => 'Gespeicherte Verbindungen';

  @override
  String get connectionNoSavedConnections => 'Keine gespeicherten Verbindungen';

  @override
  String get connectionCurrent => 'Aktuell';

  @override
  String get connectionConnected => 'Verbunden';

  @override
  String get connectionSwitchToConnection => 'Zu dieser Verbindung wechseln';

  @override
  String get connectionCloneConnection => 'Verbindung klonen';

  @override
  String get connectionCloned => 'Verbindung geklont';

  @override
  String get connectionDeleteConnectionTitle => 'Verbindung löschen';

  @override
  String get connectionDeleteConnectionConfirm =>
      'Möchten Sie die Verbindung wirklich löschen';

  @override
  String get connectionDisconnectAll => 'Alle trennen';

  @override
  String get searchDialogTitle => 'Suchen';

  @override
  String get searchHint =>
      'Nach Tabellen, Ansichten, gespeicherten Prozeduren, Spalten suchen...';

  @override
  String get searchNoResults => 'Keine Objekte gefunden';

  @override
  String get searchTryDifferentKeywords => 'Versuchen Sie andere Suchbegriffe';

  @override
  String get searchNavigate => 'Navigieren';

  @override
  String get searchSelect => 'Auswählen';

  @override
  String get searchClose => 'Schließen';

  @override
  String searchResultsCount(Object count) {
    return '$count Ergebnisse';
  }

  @override
  String get searchTypeConnection => 'Verbindung';

  @override
  String get searchTypeDatabase => 'Datenbank';

  @override
  String get searchTypeTable => 'Tabelle';

  @override
  String get searchTypeView => 'Ansicht';

  @override
  String get searchTypeProcedure => 'Gespeicherte Prozedur';

  @override
  String get searchTypeColumn => 'Spalte';

  @override
  String get savedQueriesTitle => 'Gespeicherte Abfragen';

  @override
  String get savedQueriesNoQueries => 'Keine gespeicherten Abfragen';

  @override
  String get savedQueriesDeleteTitle => 'Abfrage löschen';

  @override
  String get savedQueriesDeleteConfirm =>
      'Möchten Sie diese Abfrage wirklich löschen?';

  @override
  String get savedQueriesOpen => 'Öffnen';

  @override
  String get viewJson => 'JSON anzeigen';

  @override
  String get extractFieldAsColumn => 'Feld als Spalte extrahieren';

  @override
  String get erDiagramTitle => 'ER-Diagramm';

  @override
  String get erDiagramSearchTables => 'Tabellen suchen...';

  @override
  String get erDiagramHierarchicalLayout => 'Hierarchisches Layout';

  @override
  String get erDiagramForceDirectedLayout => 'Kraftgesteuertes Layout';

  @override
  String get erDiagramCircleLayout => 'Kreislayout';

  @override
  String get erDiagramResetLayout => 'Layout zurücksetzen';

  @override
  String get erDiagramZoomIn => 'Vergrößern';

  @override
  String get erDiagramZoomOut => 'Verkleinern';

  @override
  String get erDiagramFitToScreen => 'An Bildschirm anpassen';

  @override
  String get erDiagramRelations => 'Beziehungen';

  @override
  String get erDiagramZoom => 'Zoom';

  @override
  String get erDiagramShowIsolated => 'Isolierte anzeigen';

  @override
  String get erDiagramExportAsPNG => 'Als PNG exportieren';

  @override
  String get erDiagramExportAsJPG => 'Als JPG exportieren';

  @override
  String get erDiagramLoading => 'ER-Diagramm wird geladen...';

  @override
  String get erDiagramErrorLoading => 'Fehler beim Laden des ER-Diagramms';

  @override
  String get erDiagramNoData => 'Keine Diagrammdaten verfügbar';

  @override
  String get erDiagramRetry => 'Wiederholen';

  @override
  String get erDiagramSelectConnection => 'Verbindung auswählen';

  @override
  String get erDiagramSelectDatabase => 'Datenbank auswählen';

  @override
  String get performanceAnalyzerTitle => 'Leistungsanalysetool';

  @override
  String get performanceAnalyzerSearch => 'Suchen...';

  @override
  String get performanceAnalyzerRefresh => 'Daten aktualisieren';

  @override
  String get performanceAnalyzerGenerateReport => 'Bericht erstellen';

  @override
  String get performanceAnalyzerExport => 'Exportieren';

  @override
  String get performanceAnalyzerClose => 'Schließen';

  @override
  String get performanceAnalyzerNotConnected => 'Nicht mit Datenbank verbunden';

  @override
  String get performanceAnalyzerNotConnectedDesc =>
      'Bitte verbinden Sie zuerst eine Datenbank, um die Leistungsanalyse zu verwenden';

  @override
  String get performanceAnalyzerConfirm => 'Bestätigen';

  @override
  String get performanceAnalyzerSlowQueryAnalysis =>
      'Langsame Abfragen-Analyse';

  @override
  String get performanceAnalyzerIndexAnalysis => 'Indexanalyse';

  @override
  String get performanceAnalyzerTableStatistics => 'Tabellenstatistiken';

  @override
  String get performanceAnalyzerPerformanceReport => 'Leistungsbericht';

  @override
  String get performanceAnalyzerLoading =>
      'Datenbankleistung wird analysiert...';

  @override
  String get performanceAnalyzerLoadFailed => 'Laden fehlgeschlagen';

  @override
  String get performanceAnalyzerRetry => 'Wiederholen';

  @override
  String get performanceAnalyzerTimeThreshold => 'Zeitschwellenwert:';

  @override
  String get performanceAnalyzerNoSlowQueries =>
      'Keine langsamen Abfragen gefunden';

  @override
  String get performanceAnalyzerSelectQuery =>
      'Wählen Sie eine Abfrage aus, um Details anzuzeigen';

  @override
  String get performanceAnalyzerQueryInfo => 'Abfrageinformationen';

  @override
  String get performanceAnalyzerExecutionTime => 'Ausführungszeit';

  @override
  String get performanceAnalyzerDatabase => 'Datenbank';

  @override
  String get performanceAnalyzerRowsScaned => 'Gescannte Zeilen';

  @override
  String get performanceAnalyzerRowsReturned => 'Zurückgegebene Zeilen';

  @override
  String get performanceAnalyzerTimestamp => 'Ausführungszeit';

  @override
  String get performanceAnalyzerSqlStatement => 'SQL-Anweisung';

  @override
  String get performanceAnalyzerExecutionPlan => 'Ausführungsplan';

  @override
  String get performanceAnalyzerOptimizationSuggestions =>
      'Optimierungsvorschläge';

  @override
  String get performanceAnalyzerFullTableScan =>
      'Vollständiger Tabellenscan erkannt';

  @override
  String get performanceAnalyzerFullTableScanDesc =>
      'Abfrage verwendet vollständigen Tabellenscan (type=ALL), Index für WHERE-Spalten empfohlen';

  @override
  String get performanceAnalyzerFileSort => 'Dateisortierung';

  @override
  String get performanceAnalyzerFileSortDesc =>
      'Abfrage verwendet Dateisortierung (Using filesort), Index für ORDER BY-Spalten empfohlen';

  @override
  String get performanceAnalyzerTempTable => 'Temporäre Tabellennutzung';

  @override
  String get performanceAnalyzerTempTableDesc =>
      'Abfrage verwendet temporäre Tabelle (Using temporary), erwägen Sie Optimierung von GROUP BY oder DISTINCT-Abfragen';

  @override
  String get performanceAnalyzerLowScanEfficiency => 'Niedrige Scaneffizienz';

  @override
  String get performanceAnalyzerNoIssues =>
      'Keine offensichtlichen Probleme gefunden';

  @override
  String get performanceAnalyzerNoIssuesDesc =>
      'Abfrageausführungsplan sieht normal aus';

  @override
  String get performanceAnalyzerIndexTypeDistribution => 'Indextyp-Verteilung';

  @override
  String get performanceAnalyzerNoData => 'Keine Daten';

  @override
  String get performanceAnalyzerTotalIndexes => 'Gesamtindizes';

  @override
  String get performanceAnalyzerUsedIndexes => 'Verwendet';

  @override
  String get performanceAnalyzerUnusedIndexes => 'Unbenutzt';

  @override
  String get performanceAnalyzerIndexes => 'Indizes';

  @override
  String get performanceAnalyzerColumns => 'Spalten:';

  @override
  String get performanceAnalyzerCardinality => 'Kardinalität:';

  @override
  String get performanceAnalyzerTotalTables => 'Gesamttabellen';

  @override
  String get performanceAnalyzerTotalRows => 'Gesamtzeilen';

  @override
  String get performanceAnalyzerDataSize => 'Datengröße';

  @override
  String get performanceAnalyzerIndexSize => 'Indexgröße';

  @override
  String get performanceAnalyzerTotalSize => 'Gesamtgröße';

  @override
  String get performanceAnalyzerTableName => 'Tabellenname';

  @override
  String get performanceAnalyzerEngine => 'Engine';

  @override
  String get performanceAnalyzerRowCount => 'Zeilenanzahl';

  @override
  String get performanceAnalyzerPercentage => 'Prozentsatz';

  @override
  String get performanceAnalyzerTableSizeDistribution =>
      'Tabellengrößenverteilung (Top 10)';

  @override
  String get performanceAnalyzerDatabasePerformanceReport =>
      'Datenbankleistungsbericht';

  @override
  String get performanceAnalyzerGeneratedAt => 'Generiert am:';

  @override
  String get performanceAnalyzerTableCount => 'Tabellenanzahl';

  @override
  String get performanceAnalyzerSlowQueries => 'Langsame Abfragen';

  @override
  String get performanceAnalyzerSuggestions => 'Vorschläge';

  @override
  String get performanceAnalyzerImpact => 'Auswirkung:';

  @override
  String get performanceAnalyzerImpactHigh => 'Hoch';

  @override
  String get performanceAnalyzerImpactMedium => 'Mittel';

  @override
  String get performanceAnalyzerImpactLow => 'Niedrig';

  @override
  String get performanceAnalyzerRecommendation => 'Empfohlene Aktion:';

  @override
  String get performanceAnalyzerSlowQueriesTop => 'Langsame Abfragen Top';

  @override
  String get performanceAnalyzerLargeTableStatistics =>
      'Große Tabellenstatistiken';

  @override
  String get performanceAnalyzerClickGenerateReport =>
      'Klicken Sie auf die Schaltfläche \"Bericht erstellen\", um die Analyse zu starten';

  @override
  String get sqlHistoryTitle => 'SQL-Verlauf';

  @override
  String get sqlHistoryNoHistory => 'Kein Verlauf vorhanden';

  @override
  String get sqlHistoryClose => 'Schließen';

  @override
  String get sqlHistoryDelete => 'Löschen';

  @override
  String get sqlHistoryConfirmDelete => 'Löschen bestätigen';

  @override
  String get sqlHistoryDeleteConfirm =>
      'Möchten Sie diesen Verlaufseintrag wirklich löschen?';

  @override
  String get sqlHistoryJustNow => 'Gerade eben';

  @override
  String sqlHistoryMinutesAgo(Object count) {
    return 'Vor $count Minuten';
  }

  @override
  String sqlHistoryHoursAgo(Object count) {
    return 'Vor $count Stunden';
  }

  @override
  String sqlHistoryDaysAgo(Object count) {
    return 'Vor $count Tagen';
  }

  @override
  String get aiPanelApiSettings => 'API-Einstellungen';

  @override
  String get aiPanelApiKey => 'API-Schlüssel';

  @override
  String get aiPanelEnterApiKey => 'API-Schlüssel eingeben';

  @override
  String get aiPanelApiBaseUrl => 'API-Basis-URL (optional)';

  @override
  String get aiPanelCustomApiUrl => 'Benutzerdefinierte API-URL';

  @override
  String get aiPanelRequestTimeout => 'Anforderungszeitlimit:';

  @override
  String get aiPanelSeconds => 'Sekunden';

  @override
  String get aiPanelSave => 'Speichern';

  @override
  String get aiPanelApiSettingsSaved => 'API-Einstellungen gespeichert';

  @override
  String get aiPanelConfirmDangerousOperation =>
      'Gefährliche Operation bestätigen?';

  @override
  String get aiPanelConfirmExecuteSql => 'SQL-Ausführung bestätigen';

  @override
  String get aiPanelDangerousOperationWarning =>
      'Diese Operation könnte Daten ändern oder löschen, bitte mit Vorsicht ausführen!';

  @override
  String get aiPanelCancel => 'Abbrechen';

  @override
  String get aiPanelConfirmExecute => 'Ausführung bestätigen';

  @override
  String get aiPanelOperationCancelled => 'Operation abgebrochen';

  @override
  String get aiPanelExecutingSql => 'SQL wird ausgeführt...';

  @override
  String aiPanelExecuteSuccess(Object count) {
    return 'Ausführung erfolgreich, $count Zeilen zurückgegeben';
  }

  @override
  String get aiPanelExecuteFailed => 'Ausführung fehlgeschlagen';

  @override
  String get aiPanelDataPreview => 'Datenvorschau';

  @override
  String aiPanelAndMoreRows(Object count) {
    return 'und $count weitere Zeilen';
  }

  @override
  String aiPanelSqlExecutionSuccess(Object count) {
    return 'SQL-Ausführung erfolgreich, $count Zeilen zurückgegeben';
  }

  @override
  String get aiPanelSqlGenerationComplete => 'SQL-Generierung abgeschlossen';

  @override
  String get aiPanelSqlGenerationCompleteWarning =>
      'SQL-Generierung abgeschlossen ⚠️';

  @override
  String get aiPanelTaskCompleteDesc =>
      'Aufgabe abgeschlossen, Sie können SQL ausführen oder kopieren';

  @override
  String get aiPanelDangerousOperationDesc =>
      'Dies ist eine gefährliche Operation, bitte mit Vorsicht behandeln';

  @override
  String get aiPanelGeneratedSql => 'Generiertes SQL';

  @override
  String get aiPanelDangerous => 'Gefährlich';

  @override
  String get aiPanelContinue => 'Fortfahren';

  @override
  String get aiPanelClose => 'Schließen';

  @override
  String get aiPanelCopy => 'Kopieren';

  @override
  String get aiPanelExecute => 'Ausführen';

  @override
  String get aiPanelConfirmExecuteDangerous => 'Ausführung bestätigen';

  @override
  String get quickActionsTitle => 'Schnellaktionen';

  @override
  String get quickActionsNewTable => 'Neue Tabelle';

  @override
  String get quickActionsNewQuery => 'Neue Abfrage';

  @override
  String get quickActionsAiAssistant => 'KI-Assistent';

  @override
  String get quickActionsSelectDatabaseFirst =>
      'Bitte wählen Sie zuerst eine Datenbank aus';

  @override
  String get resultsTabResults => 'Ergebnisse';

  @override
  String get resultsTabMessages => 'Nachrichten';

  @override
  String get resultsTabExecutionPlan => 'Ausführungsplan';

  @override
  String get resultsTabExecutionDetails => 'Execution Details';

  @override
  String get resultsSearchBtn => 'Suchen';

  @override
  String get resultsSearchHint => 'Search in results…';

  @override
  String resultsSearchNoMatch(Object query) {
    return 'No rows match \"$query\"';
  }

  @override
  String get resultsClear => 'Löschen';

  @override
  String get resultsSubmit => 'Senden';

  @override
  String get resultsSearchResults => 'Ergebnisse durchsuchen';

  @override
  String get resultsViewTable => 'Tabelle';

  @override
  String get resultsViewCard => 'Karte';

  @override
  String get resultsViewChart => 'Diagramm';

  @override
  String get resultsViewStatistics => 'Statistik';

  @override
  String get paginationShowing => 'Anzeigen';

  @override
  String get paginationRows => 'Zeilen';

  @override
  String get paginationFirstPage => 'Erste Seite';

  @override
  String get paginationPreviousPage => 'Vorherige Seite';

  @override
  String get paginationNextPage => 'Nächste Seite';

  @override
  String get paginationLastPage => 'Letzte Seite';

  @override
  String get editModeTitle => 'Bearbeitungsmodus';

  @override
  String get editModeChanges => 'Änderungen';

  @override
  String get editModeHint =>
      'Doppelklick zum Bearbeiten | Enter zum Bestätigen | Esc zum Abbrechen | Tab zum Wechseln';

  @override
  String get resultsNoDataTitle => 'Keine Ergebnisse';

  @override
  String get resultsNoDataMessage =>
      'Ergebnisse werden nach der Ausführung einer Abfrage angezeigt';

  @override
  String get resultsNoDataCardMessage =>
      'Kartenansicht wird nach der Ausführung einer Abfrage angezeigt';

  @override
  String get resultsNoDataChartMessage =>
      'Diagramm wird nach der Ausführung einer Abfrage angezeigt';

  @override
  String get resultsNoDataStatisticsMessage =>
      'Statistiken werden nach der Ausführung einer Abfrage angezeigt';

  @override
  String get resultsNoDataExecutionPlanMessage =>
      'Klicken Sie auf die Schaltfläche \'Ausführungsplan\', um den Abfrageausführungsplan anzuzeigen';

  @override
  String get statisticsTotalRows => 'Gesamtzeilen';

  @override
  String get statisticsFieldInfo => 'Feldinformationen';

  @override
  String get statisticsNumeric => 'Numerisch';

  @override
  String get statisticsText => 'Text';

  @override
  String get statisticsNumericStats => 'Numerische Statistiken';

  @override
  String get statisticsCount => 'Anzahl';

  @override
  String get statisticsSum => 'Summe';

  @override
  String get statisticsAvg => 'Durchschnitt';

  @override
  String get statisticsMin => 'Minimum';

  @override
  String get statisticsMax => 'Maximum';

  @override
  String get chartXAxis => 'X-Achse';

  @override
  String get chartYAxis => 'Y-Achse';

  @override
  String get chartType => 'Typ: ';

  @override
  String get chartCannotGenerate =>
      'Diagramm kann nicht generiert werden: Bitte stellen Sie sicher, dass das Y-Achsen-Feld numerische Daten enthält';

  @override
  String messagesQuerySuccess(Object cols, Object rows) {
    return 'Abfrage erfolgreich, $rows Zeilen, $cols Spalten zurückgegeben';
  }

  @override
  String get messagesExecuteToSeeResults =>
      'Ergebnisinformationen werden nach der Ausführung einer Abfrage angezeigt';

  @override
  String sqlPreviewWillExecute(Object count, Object table) {
    return '$count SQL-Anweisungen werden in Tabelle `$table` ausgeführt:';
  }

  @override
  String get saveErrorNoTab =>
      'Speichern nicht möglich: Aktueller Tab existiert nicht';

  @override
  String get saveErrorCannotExtractTable =>
      'Speichern nicht möglich: Tabellenname kann nicht aus der Abfrage extrahiert werden';

  @override
  String saveErrorFailed(Object error) {
    return 'Speichern fehlgeschlagen: $error';
  }

  @override
  String get exportSelectFormat => 'Exportformat auswählen';

  @override
  String get toolbarExecute => 'Ausführen';

  @override
  String get toolbarStop => 'Stopp';

  @override
  String get toolbarReadOnlyChip => 'Schreibgeschützt';

  @override
  String get toolbarLimitChipTooltip =>
      'Zeilenlimit für diese Verbindung (automatisches LIMIT)';

  @override
  String get toolbarTimeoutChipTooltip =>
      'Abfrage-Timeout für diese Verbindung';

  @override
  String get toolbarChipFollowSettings => 'Einstellungen folgen';

  @override
  String get toolbarChipOff => 'Aus';

  @override
  String get toolbarChipFollowConnection => 'Verbindung folgen';

  @override
  String get gridEditBlockedReadOnly =>
      'Verbindung ist schreibgeschützt — Zellbearbeitung deaktiviert.';

  @override
  String get gridEditBlockedNoTable =>
      'Zieltabelle kann nicht ermittelt werden — Zellbearbeitung erfordert eine Ein-Tabellen-Abfrage.';

  @override
  String gridEditsCount(Object count, Object rows) {
    return '$count Änderung(en) in $rows Zeile(n)';
  }

  @override
  String get gridCommitButton => 'Änderungen übernehmen';

  @override
  String get gridDiscardButton => 'Verwerfen';

  @override
  String gridCommitSuccess(Object rows) {
    return '$rows Zeile(n) zurückgeschrieben';
  }

  @override
  String gridCommitNoPrimaryKey(Object table) {
    return 'Tabelle $table hat keinen Primärschlüssel — kein Rückschreiben möglich.';
  }

  @override
  String gridCommitFailed(Object error) {
    return 'Rückschreiben fehlgeschlagen: $error';
  }

  @override
  String get statusBarReady => 'Bereit';

  @override
  String get statusBarExecuting => 'Wird ausgeführt';

  @override
  String statusBarElapsed(String duration) {
    return 'Verstrichen $duration';
  }

  @override
  String statusBarLineCol(int line, int column) {
    return 'Zeile $line, Spalte $column';
  }

  @override
  String executionStatusBarRows(int count) {
    return '$count Zeilen';
  }

  @override
  String get executionStatusBarErrorHint =>
      'Klicken Sie auf einen Ergebnis-Tab, um Fehlerdetails zu sehen';

  @override
  String get toolbarExecutionPlan => 'Ausführungsplan';

  @override
  String get toolbarFormat => 'Formatieren';

  @override
  String get toolbarSave => 'Speichern';

  @override
  String get splitButton => 'Teilen';

  @override
  String get horizontalSplit => 'Horizontale Teilung';

  @override
  String get verticalSplit => 'Vertikale Teilung';

  @override
  String get refreshData => 'Daten aktualisieren';

  @override
  String get analyzingDatabasePerformance =>
      'Datenbankleistung wird analysiert...';

  @override
  String get fullTableScanDetected => 'Vollständiger Tabellenscan erkannt';

  @override
  String get fullTableScanDesc =>
      'Abfrage verwendet vollständigen Tabellenscan (type=ALL), Index für WHERE-Spalten empfohlen';

  @override
  String get timeThreshold => 'Zeitschwellenwert:';

  @override
  String get searchPlaceholder => 'Suchen...';

  @override
  String get closeBtn => 'Schließen';

  @override
  String get apiSettingsSavedMsg => 'API-Einstellungen gespeichert';

  @override
  String get resultsHeaderExport => 'Exportieren';

  @override
  String get resultsHeaderSearch => 'Suchen';

  @override
  String get resultsHeaderClear => 'Löschen';

  @override
  String get resultsHeaderSubmit => 'Senden';

  @override
  String get connectionStatusConnected => 'Verbunden';

  @override
  String get connectionStatusNotConnected => 'Nicht verbunden';

  @override
  String get selectConnection => 'Verbindung auswählen...';

  @override
  String get selectDatabase => 'Datenbank auswählen';

  @override
  String get aiQuickActionOptimizeSql => 'SQL optimieren';

  @override
  String get aiQuickActionExplainQuery => 'Abfrage erklären';

  @override
  String get aiQuickActionGenerateInsert => 'INSERT generieren';

  @override
  String get aiQuickActionGenerateUpdate => 'UPDATE generieren';

  @override
  String get aiQuickActionGenerateDelete => 'DELETE generieren';

  @override
  String get aiQuickActionCreateTable => 'Tabellenerstellung';

  @override
  String get aiQuickActionSecurityCheck => 'Sicherheitsprüfung';

  @override
  String get aiQuickActionIndexSuggestion => 'Indexvorschlag';

  @override
  String get aiQuickActionExecutionPlan => 'Ausführungsplan';

  @override
  String get aiQuickActionQueryHistory => 'Abfrageverlauf';

  @override
  String get shortcutCategoryQuery => 'Abfrage';

  @override
  String get queryCancelled => 'Abfrage abgebrochen';

  @override
  String queryFailed(Object error) {
    return 'Abfrage fehlgeschlagen: $error';
  }

  @override
  String querySuccessWithTime(Object count, Object time) {
    return 'Abfrage erfolgreich, $count Zeilen zurückgegeben (${time}ms)';
  }

  @override
  String get cancelingQuery => 'Abfrage wird abgebrochen...';

  @override
  String get cancelQueryFailed => 'Abfrageabbruch fehlgeschlagen';

  @override
  String get confirmCancelTransaction => 'Confirm Cancel Transaction';

  @override
  String get confirmCancelTransactionMessage =>
      'The current connection has an uncommitted transaction. Canceling the query will disconnect and reconnect, causing the transaction to rollback. Continue?';

  @override
  String get cancel => 'Cancel';

  @override
  String get explainPlanSuccess => 'Ausführungsplan erfolgreich abgerufen';

  @override
  String explainPlanFailed(Object error) {
    return 'Ausführungsplan abrufen fehlgeschlagen: $error';
  }

  @override
  String get queryEmptyCannotSave =>
      'Abfrageinhalt ist leer, kann nicht gespeichert werden';

  @override
  String get saveQueryTitle => 'Abfrage speichern';

  @override
  String get queryName => 'Abfragename';

  @override
  String get enterQueryName => 'Abfragename eingeben';

  @override
  String get saveQueryHint =>
      'Wird in der Liste der gespeicherten Abfragen gespeichert (max 20)';

  @override
  String querySaved(Object name) {
    return 'Abfrage gespeichert: $name';
  }

  @override
  String get saveQueryLimitReached =>
      'Speicherlimit erreicht (20), bitte zuerst einige Abfragen löschen';

  @override
  String savedQueryNameExists(Object name) {
    return 'Gespeicherter Abfragename \"$name\" existiert bereits für diese Verbindung';
  }

  @override
  String get sqlFormatted => 'SQL formatiert';

  @override
  String get pleaseEnterSqlCode => 'Bitte SQL-Code eingeben';

  @override
  String get noConnectedServer => 'Kein verbundener Server';

  @override
  String get split2Hint => 'Split 2 - SQL-Abfrage eingeben...';

  @override
  String get toolbarClose => 'Schließen';

  @override
  String connectedToServer(Object serverName) {
    return 'Verbunden mit $serverName';
  }

  @override
  String openTableDataFailed(Object error) {
    return 'Tabellendaten öffnen fehlgeschlagen: $error';
  }

  @override
  String queryTable(Object tableName) {
    return 'Abfrage $tableName';
  }

  @override
  String openViewFailed(Object error) {
    return 'Ansicht öffnen fehlgeschlagen: $error';
  }

  @override
  String queryView(Object viewName) {
    return 'Abfrage $viewName';
  }

  @override
  String openProcedureFailed(Object error) {
    return 'Gespeicherte Prozedur öffnen fehlgeschlagen: $error';
  }

  @override
  String callProcedure(Object procName) {
    return 'Aufruf $procName';
  }

  @override
  String get cancelConnection => 'Verbindung abbrechen';

  @override
  String get deleteConnectionTitle => 'Verbindung löschen';

  @override
  String deleteConnectionConfirm(Object serverName) {
    return 'Möchten Sie die Verbindung \"$serverName\" wirklich löschen?';
  }

  @override
  String get refresh => 'Aktualisieren';

  @override
  String get createNewTable => 'Neue Tabelle';

  @override
  String get erDiagram => 'ER-Diagramm';

  @override
  String get properties => 'Eigenschaften';

  @override
  String get exportStructure => 'Struktur exportieren';

  @override
  String get dropDatabase => 'Datenbank löschen';

  @override
  String get confirmDeleteDatabase => 'Datenbank löschen';

  @override
  String get confirmDropTable => 'Tabelle löschen';

  @override
  String typeNameToConfirm(String name) {
    return '\"$name\" zur Bestätigung eingeben';
  }

  @override
  String dropDatabaseWarning(String name) {
    return 'Datenbank \"$name\" wird dauerhaft gelöscht.';
  }

  @override
  String objectCountWarning(int count, String type) {
    return '$count $type werden zerstört';
  }

  @override
  String get allDataWillBeLost => 'Alle Daten gehen verloren';

  @override
  String copiedDbStructureToClipboard(Object dbName) {
    return 'Struktur von $dbName in Zwischenablage kopiert';
  }

  @override
  String databaseDeleted(Object dbName) {
    return 'Datenbank $dbName gelöscht';
  }

  @override
  String get browseData => 'Daten durchsuchen';

  @override
  String get editTable => 'Tabelle bearbeiten';

  @override
  String get copyTableName => 'Tabellennamen kopieren';

  @override
  String get copyColumnName => 'Spaltenname kopieren';

  @override
  String get copyIndexName => 'Indexnamen kopieren';

  @override
  String get dropColumn => 'Spalte löschen';

  @override
  String get editIndex => 'Index bearbeiten';

  @override
  String get dropIndex => 'Index löschen';

  @override
  String confirmDropColumn(Object column, Object table) {
    return 'Spalte \"$column\" aus Tabelle \"$table\" löschen?';
  }

  @override
  String confirmDropIndex(Object index) {
    return 'Index \"$index\" löschen?';
  }

  @override
  String columnDropped(Object column) {
    return 'Spalte \"$column\" gelöscht';
  }

  @override
  String indexDropped(Object index) {
    return 'Index \"$index\" gelöscht';
  }

  @override
  String dropColumnFailed(Object error) {
    return 'Spalte löschen fehlgeschlagen: $error';
  }

  @override
  String dropIndexFailed(Object error) {
    return 'Index löschen fehlgeschlagen: $error';
  }

  @override
  String get loadingSchema => 'Laden...';

  @override
  String get noColumns => 'Keine Spalten';

  @override
  String get noIndexes => 'Keine Indizes';

  @override
  String get noProgrammableObjects =>
      'Dieser Datenbanktyp unterstützt keine programmierbaren Objekte';

  @override
  String get exportData => 'Daten exportieren';

  @override
  String get dataSync => 'Datensynchronisation';

  @override
  String get rename => 'Umbenennen';

  @override
  String get truncate => 'Daten leeren';

  @override
  String get dropTable => 'Tabelle löschen';

  @override
  String loadTableStructureFailed(Object error) {
    return 'Tabellenstruktur laden fehlgeschlagen: $error';
  }

  @override
  String get tableNameCopied => 'Tabellenname kopiert';

  @override
  String copiedTableDataToClipboard(Object tableName) {
    return 'Daten von $tableName in Zwischenablage kopiert';
  }

  @override
  String tableRenamedTo(Object newName) {
    return 'Tabelle umbenannt in $newName';
  }

  @override
  String renameFailed(Object error) {
    return 'Umbenennen fehlgeschlagen: $error';
  }

  @override
  String tableTruncated(Object tableName) {
    return 'Tabelle $tableName geleert';
  }

  @override
  String truncateFailed(Object error) {
    return 'Leeren fehlgeschlagen: $error';
  }

  @override
  String tableDeleted(Object tableName) {
    return 'Tabelle $tableName gelöscht';
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
  String get indexTypeUnique => 'Eindeutig';

  @override
  String get hintIndexColumns => 'z.B.: id, name';

  @override
  String get pleaseDefineAtLeastOneColumn =>
      'Bitte definieren Sie mindestens eine Spalte';

  @override
  String tableCreated(Object tableName) {
    return 'Tabelle $tableName erfolgreich erstellt';
  }

  @override
  String createFailed(Object error) {
    return 'Erstellen fehlgeschlagen: $error';
  }

  @override
  String get tableModified => 'Tabelle erfolgreich geändert';

  @override
  String modifyFailed(Object error) {
    return 'Änderung fehlgeschlagen: $error';
  }

  @override
  String get noInformation => 'Keine Informationen';

  @override
  String get truncateTableData => 'Tabellendaten leeren';

  @override
  String get menuCut => 'Ausschneiden';

  @override
  String get menuCopy => 'Kopieren';

  @override
  String get menuPaste => 'Einfügen';

  @override
  String get menuSelectAll => 'Alles auswählen';

  @override
  String get menuFormatSql => 'SQL formatieren';

  @override
  String get menuExecuteQuery => 'Abfrage ausführen';

  @override
  String get commandNewConnection => 'Neue Verbindung';

  @override
  String get commandNewTab => 'Neuer Tab';

  @override
  String get commandExecuteQuery => 'Abfrage ausführen';

  @override
  String get commandFormatSql => 'SQL formatieren';

  @override
  String get commandToggleAiPanel => 'KI-Panel umschalten';

  @override
  String get commandQueryHistory => 'Abfrageverlauf';

  @override
  String get commandShortcuts => 'Tastenkürzel';

  @override
  String get commandSettings => 'Einstellungen';

  @override
  String get commandCategoryHistory => 'Verlauf';

  @override
  String get commandCategoryHelp => 'Hilfe';

  @override
  String get commandDescNewConnection => 'Neue Datenbankverbindung erstellen';

  @override
  String get commandDescNewTab => 'Neue Abfrage-Registerkarte erstellen';

  @override
  String get commandDescExecuteQuery => 'Aktuelle SQL-Abfrage ausführen';

  @override
  String get commandDescFormatSql => 'SQL-Code formatieren';

  @override
  String get commandDescToggleSidebar => 'Seitenleiste ein-/ausblenden';

  @override
  String get commandDescToggleAiPanel => 'KI-Assistenten-Panel ein-/ausblenden';

  @override
  String get commandDescQueryHistory => 'Ausführungsverlauf anzeigen';

  @override
  String get commandDescShortcuts => 'Alle Tastenkürzel anzeigen';

  @override
  String get commandDescSettings => 'Anwendungseinstellungen öffnen';

  @override
  String get searchNavigateKeys => '↑↓/Maus';

  @override
  String get menuConnect => 'Verbinden';

  @override
  String get menuCancelConnection => 'Verbindung abbrechen';

  @override
  String get menuDisconnect => 'Trennen';

  @override
  String get menuRefresh => 'Aktualisieren';

  @override
  String get menuEditConnection => 'Verbindung bearbeiten';

  @override
  String get menuCloneConnection => 'Verbindung klonen';

  @override
  String get menuDeleteConnection => 'Verbindung löschen';

  @override
  String get addColumn => 'Spalte hinzufügen';

  @override
  String get addIndex => 'Index hinzufügen';

  @override
  String get noIndexesClickToAdd =>
      'Keine Indizes, klicken Sie auf die Schaltfläche oben, um hinzuzufügen';

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
      'CSV ist ein universelles Tabellenkalkulationsformat, kompatibel mit Excel, Numbers, Google Sheets usw.';

  @override
  String get formatJSONDesc =>
      'JSON ist ein strukturiertes Datenformat, geeignet für Programmlesevorgänge oder API-Aufrufe.';

  @override
  String get formatExcelDesc =>
      'Das Excel-Format behält Datentypen und Formatierung bei, geeignet für tiefgreifende Datenanalysen.';

  @override
  String get formatMarkdownDesc =>
      'Das Markdown-Tabellenformat ist geeignet für Dokumente, Berichte oder Code-Reviews.';

  @override
  String get formatSqlInsertDesc =>
      'SQL INSERT-Anweisungen können direkt in andere Datenbanken importiert werden, geeignet für Datenmigrationen.';

  @override
  String get copiedToClipboard => 'In Zwischenablage kopiert';

  @override
  String get hintFormatName => 'z.B.: Mein Format';

  @override
  String get hintOptionalDescription => 'Optionale Beschreibung';

  @override
  String get formatterSelectPreset => 'Voreinstellung auswählen';

  @override
  String get formatterFormat => 'Formatieren';

  @override
  String get formatterCopyResult => 'Ergebnis kopieren';

  @override
  String get formatterHintInputSql => 'Geben Sie hier SQL-Code ein...';

  @override
  String get formatterSpace => 'Leerzeichen';

  @override
  String get formatterTab => 'Tab';

  @override
  String get formatterIndentSize => 'Einzugsgröße';

  @override
  String get formatterMaxLineLength => 'Maximale Zeilenlänge';

  @override
  String get formatterUppercaseKeywords => 'Schlüsselwörter großschreiben';

  @override
  String get formatterAlignKeywords => 'Schlüsselwörter ausrichten';

  @override
  String get formatterPreserveComments => 'Kommentare beibehalten';

  @override
  String get formatterNewlineBeforeParentheses => 'Zeilenumbruch vor Klammern';

  @override
  String get formatterCompactMode => 'Kompaktmodus';

  @override
  String get formatterPosition => 'Position';

  @override
  String get formatterEnd => 'Ende';

  @override
  String get formatterStart => 'Anfang';

  @override
  String loadFailed(Object error) {
    return 'Laden fehlgeschlagen';
  }

  @override
  String exportFailed(String error) {
    return 'Export fehlgeschlagen: $error';
  }

  @override
  String timeAgoDays(Object count) {
    return 'Tage';
  }

  @override
  String timeAgoHours(Object count) {
    return 'Stunden';
  }

  @override
  String timeAgoMinutes(Object count) {
    return 'Minuten';
  }

  @override
  String get timeAgoJustNow => 'Gerade eben';

  @override
  String get optimizationFullTableScan => 'Vollständiger Tabellenscan';

  @override
  String get optimizationFullTableScanDesc =>
      'Die Abfrage verwendet einen vollständigen Tabellenscan (type=ALL). Es wird empfohlen, einen Index für die WHERE-Spalten hinzuzufügen.';

  @override
  String get optimizationFilesort => 'Dateisortierung';

  @override
  String get optimizationFilesortDesc =>
      'Die Abfrage verwendet Dateisortierung (Using filesort). Es wird empfohlen, einen Index für die ORDER BY-Spalten hinzuzufügen.';

  @override
  String get optimizationTemporary => 'Temporäre Tabelle';

  @override
  String get optimizationTemporaryDesc =>
      'Die Abfrage verwendet eine temporäre Tabelle (Using temporary). Erwägen Sie die Optimierung von GROUP BY- oder DISTINCT-Abfragen.';

  @override
  String get optimizationLowEfficiency => 'Niedrige Effizienz';

  @override
  String optimizationLowEfficiencyDesc(
    Object ratio,
    Object rowsExamined,
    Object rowsSent,
  ) {
    return 'Die Abfrage hat eine niedrige Scaneffizienz. Es wird empfohlen, die Abfragebedingungen zu optimieren.';
  }

  @override
  String get optimizationNoIssue => 'Keine Probleme';

  @override
  String get optimizationNoIssueDesc =>
      'Keine offensichtlichen Leistungsprobleme festgestellt';

  @override
  String get optimizationSuggestions => 'Optimierungsvorschläge';

  @override
  String get indexTypeDistribution => 'Indextyp-Verteilung';

  @override
  String get noData => 'Keine Daten';

  @override
  String get indexPrimary => 'Primär';

  @override
  String get indexUnique => 'Eindeutig';

  @override
  String get indexNormal => 'Normal';

  @override
  String get totalIndexes => 'Gesamtindizes';

  @override
  String get indexUsed => 'Verwendet';

  @override
  String get indexUnused => 'Unbenutzt';

  @override
  String indexCount(Object count) {
    return 'Indexanzahl';
  }

  @override
  String columnCardinality(Object cardinality) {
    return 'Spaltenkardinalität';
  }

  @override
  String columnsLabel(Object columns) {
    return 'Spalten';
  }

  @override
  String get totalTables => 'Gesamttabellen';

  @override
  String get totalRows => 'Gesamtzeilen';

  @override
  String get dataSize => 'Datengröße';

  @override
  String get indexSize => 'Indexgröße';

  @override
  String get tableSizeDistribution => 'Tabellengrößenverteilung';

  @override
  String get tableNameLabel => 'Tabellenname';

  @override
  String get tableEngineLabel => 'Engine';

  @override
  String get tableRowCountLabel => 'Zeilenanzahl';

  @override
  String get tableDataSizeLabel => 'Datengröße';

  @override
  String get tableIndexSizeLabel => 'Indexgröße';

  @override
  String get tableTotalSizeLabel => 'Gesamtgröße';

  @override
  String get tableRatioLabel => 'Verhältnis';

  @override
  String get databasePerformanceReport => 'Datenbankleistungsbericht';

  @override
  String databaseLabel(Object name) {
    return 'Datenbank';
  }

  @override
  String generatedAtLabel(Object time) {
    return 'Generiert am';
  }

  @override
  String get tableCountLabel => 'Tabellenanzahl';

  @override
  String get slowQueryCountLabel => 'Langsame Abfragen';

  @override
  String get suggestionCountLabel => 'Vorschläge';

  @override
  String impactLevel(Object level) {
    return 'Auswirkungsgrad';
  }

  @override
  String get impactHigh => 'Hoch';

  @override
  String get impactMedium => 'Mittel';

  @override
  String get impactLow => 'Niedrig';

  @override
  String get recommendedAction => 'Empfohlene Aktion';

  @override
  String slowQueryTopN(Object count) {
    return 'Langsame Abfragen Top';
  }

  @override
  String get largeTableStats => 'Große Tabellenstatistiken';

  @override
  String get tabRenameTitle => 'Abfrage umbenennen';

  @override
  String get tabRenameHint => 'Abfragenamen eingeben';

  @override
  String get tabRename => 'Umbenennen';

  @override
  String get tabClose => 'Schließen';

  @override
  String get tabCloseOthers => 'Andere schließen';

  @override
  String get tabCloseToRight => 'Rechte schließen';

  @override
  String get tabCloseAll => 'Alle schließen';

  @override
  String get tabDuplicate => 'Tab duplizieren';

  @override
  String get tabNewTooltip => 'Neue Abfrage (Strg+T)';

  @override
  String tabNewQueryTitle(Object count) {
    return 'Abfrage $count';
  }

  @override
  String get confirm => 'Bestätigen';

  @override
  String get copySuffix => '(Kopie)';

  @override
  String get triggerTitle => 'Trigger';

  @override
  String triggerFailedToLoad(Object error) {
    return 'Trigger konnten nicht geladen werden: $error';
  }

  @override
  String get triggerFailedToLoadDefinition =>
      'Trigger-Definition konnte nicht geladen werden';

  @override
  String get triggerDeleteTitle => 'Trigger löschen';

  @override
  String triggerDeleteConfirm(Object name) {
    return 'Möchten Sie den Trigger \"$name\" wirklich löschen?';
  }

  @override
  String triggerDeleted(Object name) {
    return 'Trigger \"$name\" gelöscht';
  }

  @override
  String triggerDeleteFailed(Object error) {
    return 'Trigger konnte nicht gelöscht werden: $error';
  }

  @override
  String get triggerCannotDisable =>
      'MySQL-Trigger können nicht direkt deaktiviert werden. Verwenden Sie Löschen zum Entfernen.';

  @override
  String get triggerShowList => 'Liste anzeigen';

  @override
  String get triggerGroupByTable => 'Nach Tabelle gruppieren';

  @override
  String get triggerSearchHint => 'Trigger suchen...';

  @override
  String get triggerNoTriggers => 'Keine Trigger gefunden';

  @override
  String get triggerCreate => 'Trigger erstellen';

  @override
  String get triggerViewDefinition => 'Definition anzeigen';

  @override
  String get triggerCopyName => 'Name kopieren';

  @override
  String triggerCopied(Object name) {
    return '\"$name\" in die Zwischenablage kopiert';
  }

  @override
  String get triggerNew => 'Neuer Trigger';

  @override
  String triggerDefinition(Object name) {
    return 'Trigger: $name';
  }

  @override
  String get formatterSqlFormat => 'SQL Format';

  @override
  String get formatterSavePreset => 'Vorlage speichern';

  @override
  String get formatterPresetName => 'Vorlagenname';

  @override
  String get formatterCustomPreset => 'Benutzerdefinierte Vorlage';

  @override
  String get formatterBuiltIn => 'Eingebaut';

  @override
  String get formatterSaveAsPreset =>
      'Aktuelle Einstellungen als Vorlage speichern';

  @override
  String get formatterDeletePreset => 'Vorlage löschen';

  @override
  String get formatterInput => 'Eingabe';

  @override
  String get formatterOptions => 'Formatierungsoptionen';

  @override
  String get formatterIndent => 'Einzug';

  @override
  String get formatterKeywords => 'Schlüsselwörter';

  @override
  String get formatterCommaStyle => 'Komma-Stil';

  @override
  String get formatterApplyToEditor => 'Auf Editor anwenden';

  @override
  String filterTitle(String columnName) {
    return 'Filter: $columnName';
  }

  @override
  String get filterEquals => 'gleich';

  @override
  String get filterNotEquals => 'nicht gleich';

  @override
  String get filterContains => 'enthält';

  @override
  String get filterNotContains => 'nicht enthält';

  @override
  String get filterGreaterThan => 'größer als';

  @override
  String get filterLessThan => 'kleiner als';

  @override
  String get filterIsEmpty => 'ist leer';

  @override
  String get filterIsNotEmpty => 'ist nicht leer';

  @override
  String get filterRegex => 'regex';

  @override
  String get filterValue => 'Wert';

  @override
  String get filterEnterValue => 'Filterwert eingeben';

  @override
  String get filterCaseSensitive => 'Groß-/Kleinschreibung';

  @override
  String get filterTimeFilter => 'Zeitfilter';

  @override
  String get filterToday => 'Heute';

  @override
  String get filterLast24Hours => 'Letzte 24 Stunden';

  @override
  String get filterLast7Days => 'Letzte 7 Tage';

  @override
  String get filterLast30Days => 'Letzte 30 Tage';

  @override
  String rowCountLabel(Object count) {
    return '$count Zeilen';
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
  String get aiPanelCustomModel => 'Benutzerdefiniertes Modell';

  @override
  String get aiPanelBookmarks => 'Lesezeichen';

  @override
  String get aiPanelScrollToMessageDeveloping =>
      'Scrollen zur Nachrichtenfunktion in Entwicklung';

  @override
  String get aiPanelBranchConversationCreated => 'Zweigkonversation erstellt';

  @override
  String get aiPanelNoConnections =>
      'Keine Verbindungen, bitte in Verbindungsverwaltung erstellen';

  @override
  String get aiPanelConversationList => 'Konversationsliste';

  @override
  String get aiPanelSelectConnection => 'Verbindung auswählen';

  @override
  String get aiPanelNoConnection => 'Keine Verbindung';

  @override
  String get aiPanelSelectDatabaseFirst => 'Verbindung zuerst auswählen';

  @override
  String get aiPanelSelectDatabase => 'Datenbank auswählen';

  @override
  String get aiPanelAllDatabases => 'Alle Datenbanken';

  @override
  String get aiPanelConnectionFailed => 'Verbindung fehlgeschlagen';

  @override
  String get aiPanelUnknownError => 'Unbekannter Fehler';

  @override
  String get aiPanelLoadDatabasesFailed =>
      'Datenbanken konnten nicht geladen werden';

  @override
  String get aiPanelDangerousOperation => 'Gefährliche Operation';

  @override
  String get aiPanelOptimizeSql => 'SQL optimieren';

  @override
  String get aiPanelSecurityAnalysis => 'Sicherheitsanalyse';

  @override
  String get aiPanelExecutionPlan => 'Ausführungsplan';

  @override
  String get aiPanelIndexSuggestions => 'Indexvorschläge';

  @override
  String get aiPanelInputHint =>
      'Bitte geben Sie Ihre Datenbankfrage ein, z.B.: Wie optimiere ich diese Abfrage?';

  @override
  String get aiPanelStop => 'Stop';

  @override
  String get aiPanelSend => 'Senden';

  @override
  String get aiPanelSelectConnectionFirst =>
      'Bitte wählen Sie zuerst eine Verbindungsinstanz aus dem Dropdown oben aus.';

  @override
  String aiPanelConnectionNotAvailable(Object name) {
    return 'Verbindungsinstanz \"$name\" ist nicht verbunden oder nicht verfügbar, bitte verbinden Sie sie zuerst.';
  }

  @override
  String get aiPanelTable => 'Tabelle';

  @override
  String get aiPanelDangerousOperationBadge => 'Gefährliche Operation';

  @override
  String get aiPanelThinkingProcess => 'Denkprozess';

  @override
  String get aiPanelExpandThinking => 'Denkprozess erweitern';

  @override
  String get aiPanelCollapseThinking => 'Denkprozess einklappen';

  @override
  String get aiPanelRenameSession => 'Sitzung umbenennen';

  @override
  String get aiPanelSessionTitle => 'Sitzungstitel';

  @override
  String get aiPanelDeleteSession => 'Sitzung löschen';

  @override
  String aiPanelDeleteSessionConfirm(Object name) {
    return 'Sind Sie sicher, dass Sie \"$name\" löschen möchten?';
  }

  @override
  String get aiPanelRename => 'Umbenennen';

  @override
  String get aiPanelUnarchive => 'Dearchivieren';

  @override
  String get aiPanelArchive => 'Archivieren';

  @override
  String get aiPanelSessions => 'Sitzungen';

  @override
  String get aiPanelSearchSessions => 'Sitzungen suchen';

  @override
  String get aiPanelNoSessions => 'Keine Sitzungen';

  @override
  String aiPanelArchivedSessions(Object count) {
    return 'Archivierte Sitzungen ($count)';
  }

  @override
  String get aiPanelJustNow => 'Gerade eben';

  @override
  String aiPanelMinutesAgo(Object count) {
    return 'Vor $count Minuten';
  }

  @override
  String aiPanelHoursAgo(Object count) {
    return 'Vor $count Stunden';
  }

  @override
  String aiPanelDaysAgo(Object count) {
    return 'Vor $count Tagen';
  }

  @override
  String get aiPanelSelectProvider => 'Anbieter auswählen';

  @override
  String aiPanelSelectModelCurrent(Object provider) {
    return 'Modell auswählen (Aktuell: $provider)';
  }

  @override
  String aiPanelApiConfigCurrent(Object provider) {
    return 'API-Konfiguration (Aktuell: $provider)';
  }

  @override
  String get aiPanelModelProviderMismatch =>
      'Ausgewähltes Modell gehört nicht zum ausgewählten Anbieter';

  @override
  String get aiPanelAllowSession => 'Diese Sitzung erlauben';

  @override
  String get aiPanelNoBookmarks => 'Keine Lesezeichen';

  @override
  String get aiPanelClickBookmarkIcon =>
      'Klicken Sie auf das Lesezeichensymbol einer Nachricht, um hinzuzufügen';

  @override
  String get aiCmdOptimizeSql => 'SQL-Anweisung optimieren';

  @override
  String get aiCmdExplainQuery => 'Abfrageplan erklären';

  @override
  String get aiCmdGenerateCrud => 'CRUD-Anweisungen generieren';

  @override
  String get aiCmdAnalyzeTable => 'Tabellenstruktur analysieren';

  @override
  String get aiCmdShowHistory => 'Abfrageverlauf anzeigen';

  @override
  String get aiCmdShowBookmarks => 'Lesezeichen anzeigen';

  @override
  String get aiCmdBranchConversation => 'Zweigkonversation erstellen';

  @override
  String get aiCmdListDatabases => 'List all databases';

  @override
  String get aiCmdListTables => 'List all tables';

  @override
  String get settingsThemeMode => 'Themenmodus';

  @override
  String get settingsThemeColor => 'Akzentfarbe';

  @override
  String get settingsSystem => 'System';

  @override
  String get settingsPreview => 'Vorschau';

  @override
  String get settingsPrimaryButton => 'Primärer Button';

  @override
  String get settingsSecondaryButton => 'Sekundärer Button';

  @override
  String get settingsApply => 'Anwenden';

  @override
  String get colorBlue => 'Blau';

  @override
  String get colorPurple => 'Lila';

  @override
  String get colorGreen => 'Grün';

  @override
  String get colorOrange => 'Orange';

  @override
  String get colorRed => 'Rot';

  @override
  String get colorCyan => 'Cyan';

  @override
  String get colorPink => 'Pink';

  @override
  String get colorYellow => 'Gelb';

  @override
  String get aiChatPageTitle => 'KI-Assistent';

  @override
  String get messageLabelYou => 'Sie';

  @override
  String get messageLabelAi => 'KI';

  @override
  String get messageStatusSending => 'Senden';

  @override
  String get messageStatusGenerating => 'Generieren';

  @override
  String get messageStatusFailed => 'Fehlgeschlagen';

  @override
  String get messageStatusCancelled => 'Abgebrochen';

  @override
  String get messageStatusError => 'Fehler';

  @override
  String get messageStatusThinking => 'Denken';

  @override
  String tokenUsagePrompt(int count) {
    return 'Eingabe $count';
  }

  @override
  String tokenUsageCompletion(int count) {
    return 'Ausgabe $count';
  }

  @override
  String tokenUsageTotal(int count) {
    return 'Gesamt $count';
  }

  @override
  String sessionTokenUsage(
    int promptTokens,
    int completionTokens,
    int totalTokens,
  ) {
    return 'Sitzung: Eingabe $promptTokens · Ausgabe $completionTokens · Gesamt $totalTokens';
  }

  @override
  String get messageActionRegenerate => 'Neu generieren';

  @override
  String get tooltipCopyCode => 'Code kopieren';

  @override
  String get tooltipExecuteCode => 'Code ausführen';

  @override
  String get messageCopied => 'Kopiert';

  @override
  String toolCallTitle(String name) {
    return 'Werkzeug: $name';
  }

  @override
  String toolResultTitle(String name) {
    return 'Ergebnis: $name';
  }

  @override
  String get toolCallCompleted => 'Aufgerufen und abgeschlossen';

  @override
  String get toolParamLabel => 'Parameter';

  @override
  String get toolResultLabel => 'Ergebnis';

  @override
  String get toolGroupTitle => 'Werkzeuggruppe';

  @override
  String toolGroupSummary(int count) {
    return '$count Werkzeuge ausgeführt';
  }

  @override
  String toolGroupItemTitle(int index, String name) {
    return 'Werkzeug $index: $name';
  }

  @override
  String get toolNoParams => 'Keine Parameter';

  @override
  String get aiWelcomeTitle => 'KI-Datenbankassistent';

  @override
  String get aiWelcomeDescription =>
      'Ich kann Ihnen helfen, SQL zu schreiben, Abfragen zu optimieren, Tabellenstrukturen zu analysieren, Sicherheitsprobleme zu überprüfen oder alle datenbankbezogenen Fragen zu beantworten.';

  @override
  String aiConnectedTo(String name) {
    return 'Verbunden: $name';
  }

  @override
  String get aiExampleSectionTitle => 'Fragen Sie mich';

  @override
  String get aiQuickActionsSectionTitle => 'Schnellaktionen';

  @override
  String get aiTipQuickSend => 'Strg + Enter zum Senden';

  @override
  String get aiTipSlashCommands => 'Geben Sie / ein, um alle Befehle zu sehen';

  @override
  String get aiExampleQuestion1 => 'Optimieren Sie die Leistung dieser Abfrage';

  @override
  String get aiExampleQuestion2 => 'Aktuelle Tabellenstruktur analysieren';

  @override
  String get aiExampleQuestion3 => 'Überprüfen Sie die Sicherheit dieses SQL';

  @override
  String get errorApiKeyRequired =>
      'Bitte geben Sie zuerst den API-Schlüssel ein';

  @override
  String get errorBaseUrlRequired => 'Bitte geben Sie zuerst die Basis-URL ein';

  @override
  String errorFetchModelsFailed(String error) {
    return 'Fehler beim Abrufen der Modellliste: $error';
  }

  @override
  String get tooltipRefreshModels => 'Modellliste aktualisieren';

  @override
  String get labelCustomModelInput => 'Modellnamen manuell eingeben';

  @override
  String get tooltipAddModel => 'Modell hinzufügen';

  @override
  String get hintFetchOrInputModel =>
      'Klicken Sie auf Aktualisieren, um abzurufen, oder geben Sie den Modellnamen manuell ein';

  @override
  String get hintFetchModels =>
      'Klicken Sie auf Aktualisieren, um die Modellliste abzurufen';

  @override
  String get errorSelectModelRequired =>
      'Bitte wählen oder geben Sie ein Modell ein';

  @override
  String errorSaveFailed(String error) {
    return 'Speichern fehlgeschlagen: $error';
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
    return 'Datei ausgewählt: $name';
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
  String get smartImportAiInferringTable => 'KI leitet Tabellennamen ab...';

  @override
  String smartImportAiSuggestedTable(String name) {
    return 'KI schlägt Tabellennamen vor: $name';
  }

  @override
  String get smartImportDoNotImport => 'Nicht importieren';

  @override
  String smartImportTaskDescription(int count, String table) {
    return 'Importiere $count nach $table';
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
  String get smartImportAiModel => 'AI-Modell';

  @override
  String get aiPanelFullscreen => 'Vollbild';

  @override
  String get aiPanelExitFullscreen => 'Vollbild beenden';

  @override
  String get aiPanelOpenInNewQuery => 'In neuer Abfrage geöffnet';

  @override
  String aiPanelInsertStatementsGenerated(int count, String tableName) {
    return 'AI hat $count INSERT-Anweisungen generiert, bereit zum Einfügen in Tabelle [$tableName].';
  }

  @override
  String get aiPanelSqlPreviewTitle => 'SQL-Vorschau (erste 3):';

  @override
  String aiPanelMoreStatements(int count) {
    return '... und $count weitere Anweisungen';
  }

  @override
  String aiAgentToolCallLimitReached(int count) {
    return 'KI-Assistent hat das Tool-Aufruf-Limit ($count Mal) erreicht. Bitte vereinfachen Sie Ihre Frage oder fahren Sie schrittweise fort.';
  }

  @override
  String get aiAgentMaxIterationsReached =>
      'Agent hat maximale Iterationen erreicht und konnte das Gespräch nicht abschließen.';

  @override
  String get aiAgentDuplicateQuery =>
      'Diese Abfrage wurde bereits ausgeführt. Bitte antworten Sie direkt basierend auf den vorhandenen Ergebnissen, ohne die gleiche Information erneut abzufragen.';

  @override
  String aiAgentToolExecutionFailed(String error) {
    return 'Tool-Ausführung fehlgeschlagen: $error';
  }

  @override
  String aiAgentUnknownTool(String name) {
    return 'Unbekanntes Tool: $name';
  }

  @override
  String aiContextCurrentDatabase(String name) {
    return 'Aktuelle Datenbank: $name';
  }

  @override
  String aiContextCurrentTable(String name) {
    return 'Aktuelle Tabelle: $name';
  }

  @override
  String aiContextRecentQueries(String queries) {
    return 'Kürzliche Abfragen: $queries';
  }

  @override
  String aiContextGoalSummary(String summary) {
    return 'Zielzusammenfassung der aktuellen Sitzung: $summary';
  }

  @override
  String get taskPanelTitle => 'Aufgaben';

  @override
  String get taskPanelEmpty => 'Keine Aufgaben';

  @override
  String get taskPanelEmptyDesc =>
      'Import- oder Exportvorgänge werden hier angezeigt';

  @override
  String get taskPanelClearCompleted => 'Abgeschlossene löschen';

  @override
  String get taskPanelStatusPending => 'Ausstehend';

  @override
  String get taskPanelStatusRunning => 'Wird ausgeführt';

  @override
  String get taskPanelStatusPaused => 'Pausiert';

  @override
  String get taskPanelStatusCompleted => 'Abgeschlossen';

  @override
  String get taskPanelStatusFailed => 'Fehlgeschlagen';

  @override
  String get taskPanelStatusCancelled => 'Abgebrochen';

  @override
  String get taskTypeImport => 'Import';

  @override
  String get taskTypeExport => 'Export';

  @override
  String get taskTypeQuery => 'Abfrage';

  @override
  String get taskActionCancel => 'Abbrechen';

  @override
  String get taskActionRetry => 'Wiederholen';

  @override
  String get taskActionRemove => 'Löschen';

  @override
  String get taskActionOpenFolder => 'Ordner öffnen';

  @override
  String get taskCreateExportTitle => 'Exportaufgabe erstellen';

  @override
  String get taskCreateExportFormat => 'Exportformat';

  @override
  String get taskCreateExportPath => 'Ausgabepfad';

  @override
  String get taskCreateExportPathPlaceholder =>
      'Klicken Sie auf die Schaltfläche rechts, um den Speicherort auszuwählen';

  @override
  String get taskCreateExportPathSelect => 'Speicherort auswählen';

  @override
  String get taskCreateExportStart => 'Aufgabe erstellen';

  @override
  String get taskValidationPathRequired => 'Bitte wählen Sie einen Ausgabepfad';

  @override
  String get taskValidationPathNotWritable =>
      'Verzeichnis ist nicht beschreibbar, bitte wählen Sie einen anderen Ort';

  @override
  String get taskValidationPathExists =>
      'Datei existiert bereits und wird überschrieben';

  @override
  String taskStatusBarTasks(int count) {
    return '$count Aufgaben';
  }

  @override
  String taskStatusBarRunning(int count) {
    return '$count wird ausgeführt';
  }

  @override
  String get taskLogInfo => 'Info';

  @override
  String get taskLogWarning => 'Warnung';

  @override
  String get taskLogError => 'Fehler';

  @override
  String get taskLogSuccess => 'Erfolg';

  @override
  String get taskDetailTitle => 'Aufgabendetails';

  @override
  String get taskDetailBasicInfo => 'Grundinformationen';

  @override
  String get taskDetailStatistics => 'Ausführungsstatistik';

  @override
  String get taskDetailError => 'Fehlermeldung';

  @override
  String get taskDetailOutputFile => 'Ausgabedatei';

  @override
  String get taskDetailLogs => 'Ausführungsprotokolle';

  @override
  String get taskDetailCopied => 'Pfad in Zwischenablage kopiert';

  @override
  String get taskPhaseAnalyzing => 'Wird analysiert...';

  @override
  String get taskPhaseQuerying => 'Daten werden abgefragt...';

  @override
  String get taskPhaseFormatting => 'Daten werden formatiert...';

  @override
  String get taskPhaseWriting => 'Datei wird geschrieben...';

  @override
  String get taskPhaseCompleted => 'Abgeschlossen';

  @override
  String get aiExportButtonCreate => 'Exportaufgabe erstellen';

  @override
  String get aiExportButtonAnalyzing => 'Wird analysiert...';

  @override
  String get aiMessageExportAction => 'Diese Daten exportieren';

  @override
  String get smartImportCreateTask => 'Importaufgabe im Hintergrund erstellen';

  @override
  String get schemaDiffTitle => 'Schema-Vergleich & Synchronisation';

  @override
  String get schemaDiffMenuItem => 'Schema-Vergleich & Synchronisation';

  @override
  String get schemaDiffSource => 'Quelle';

  @override
  String get schemaDiffTarget => 'Ziel';

  @override
  String get schemaDiffCompareButton => 'Vergleichen';

  @override
  String get schemaDiffSelectDatabases =>
      'Wählen Sie Quell- und Zieldatenbank zum Vergleich';

  @override
  String get schemaDiffTabOverview => 'Übersicht';

  @override
  String get schemaDiffTabDetails => 'Details';

  @override
  String get schemaDiffTabSync => 'Synchronisation';

  @override
  String get sidebarColumns => 'Spalten';

  @override
  String get sidebarIndexes => 'Indizes';

  @override
  String get sidebarInsertIntoEditor => 'In Editor einfügen';

  @override
  String get sidebarForeignKeys => 'Fremdschlüssel';

  @override
  String get sidebarCopyIndexName => 'Indexnamen kopieren';

  @override
  String get sidebarCopyForeignKeyName => 'Fremdschlüsselnamen kopieren';

  @override
  String get sidebarCopyName => 'Namen kopieren';

  @override
  String get sidebarReadOnlyConnection => 'Schreibgeschützte Verbindung';

  @override
  String get sidebarCopyColumnName => 'Spaltennamen kopieren';

  @override
  String get sidebarCopyColumnType => 'Spaltentyp kopieren';

  @override
  String get sidebarCopyAllColumnNames => 'Alle Spaltennamen kopieren';

  @override
  String get sidebarOpenEditorFirst => 'Zuerst einen Abfrage-Reiter öffnen';

  @override
  String get sidebarEvents => 'Ereignisse';

  @override
  String get sidebarProgrammableObjects => 'Programmierbare Objekte';

  @override
  String get selectDatabaseHint =>
      'Doppelklicken Sie auf eine Datenbank, um deren Objekte anzuzeigen';

  @override
  String get workspaceEmptyTitle => 'Keine offenen Abfragen';

  @override
  String get workspaceEmptyHint =>
      'Erstellen Sie eine neue Abfrage-Registerkarte, um zu beginnen';

  @override
  String get noSearchResults => 'Keine Treffer';

  @override
  String get page => 'Seite';

  @override
  String get settingsSubscriptionSettings => 'Abonnement';

  @override
  String get settingsFreePlan => 'Kostenlos';

  @override
  String get settingsFreePlanDesc =>
      'Sie befinden sich aktuell im kostenlosen Plan';

  @override
  String get settingsProActivated => 'Pro aktiviert';

  @override
  String get settingsProActivatedDesc =>
      'Alle Pro-Funktionen sind freigeschaltet';

  @override
  String get settingsUpgradeToPro => 'Upgrade auf Pro';

  @override
  String get settingsRestorePurchases => 'Käufe wiederherstellen';

  @override
  String get purchaseDialogTitle => 'Upgrade auf Pro';

  @override
  String get purchaseDialogDesc =>
      'Schalten Sie alle Premium-Funktionen mit einem Pro-Abonnement frei';

  @override
  String get purchaseDialogNoProducts => 'Keine Produkte verfügbar';

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
  String get recentTables => 'Zuletzt';

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
  String get unsavedChangesTitle => 'Nicht gespeicherte Änderungen';

  @override
  String get unsavedChangesMessage =>
      'Dieser Tab hat nicht gespeicherte Änderungen. Schließen ohne Speichern?';

  @override
  String get discardChanges => 'Verwerfen';

  @override
  String tabCloseConfirmMessage(String title) {
    return 'Möchten Sie die Änderungen an \"$title\" vor dem Schließen speichern?';
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
  String get exportConnectionsTitle => 'Verbindungen exportieren';

  @override
  String get importConnectionsTitle => 'Verbindungen importieren';

  @override
  String get exportConnectionsCount => 'Zu exportierende Verbindungen';

  @override
  String get exportPasswordHint => 'Sicherungskennwort';

  @override
  String get confirmExportPasswordHint => 'Sicherungskennwort bestätigen';

  @override
  String get passwordsDoNotMatch => 'Kennwörter stimmen nicht überein';

  @override
  String get importPasswordHint => 'Sicherungskennwort';

  @override
  String get selectExportFile => 'In Datei speichern';

  @override
  String get selectImportFile => 'Sicherungsdatei auswählen';

  @override
  String selectImportFileFailed(String error) {
    return 'Dateiauswahl fehlgeschlagen: $error';
  }

  @override
  String get conflictStrategyLabel => 'Wenn Verbindungsname bereits existiert';

  @override
  String get conflictStrategySkip => 'Überspringen';

  @override
  String get conflictStrategyRename => 'Umbenennen';

  @override
  String get conflictStrategyOverwrite => 'Überschreiben';

  @override
  String get exportSuccess => 'Verbindungen erfolgreich exportiert';

  @override
  String get importSuccess => 'Verbindungen erfolgreich importiert';

  @override
  String get invalidPassword => 'Ungültiges Kennwort';

  @override
  String get invalidFile => 'Ungültige oder beschädigte Sicherungsdatei';

  @override
  String get noConnectionsToExport => 'Keine Verbindungen zum Exportieren';

  @override
  String get exportThisConnection => 'Diese Verbindung exportieren';

  @override
  String get commandCategoryTools => 'Werkzeuge';

  @override
  String get passwordRequiredTitle => 'Passwort erforderlich';

  @override
  String passwordRequiredMessage(String serverName) {
    return 'Geben Sie das Passwort für $serverName ein, um eine Verbindung herzustellen';
  }

  @override
  String get connectionConnectNoPassword => 'Ohne Passwort verbinden';

  @override
  String get embeddedRequiresRemoteServer => 'Nur Remote-Server';

  @override
  String get serverSessionExpiredTitle => 'Sitzung abgelaufen';

  @override
  String get serverSessionExpiredMessage =>
      'Ihre Serversitzung ist abgelaufen oder wurde widerrufen. Bitte melden Sie sich erneut an.';

  @override
  String get serverSessionRelogin => 'Erneut anmelden';

  @override
  String get serverReconnectLastSession => 'Mit letztem Server verbinden';

  @override
  String get serverReconnectFailed =>
      'Die gespeicherte Sitzung ist nicht mehr gültig. Bitte melden Sie sich erneut an.';

  @override
  String sidebarEmptyTableFailed(String error) {
    return 'Failed to empty table: $error';
  }

  @override
  String sidebarDropViewFailed(String error) {
    return 'Löschen der Ansicht fehlgeschlagen: $error';
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
    return 'Möchten Sie die Ansicht \"$viewName\" wirklich löschen?\n\nDiese Aktion kann nicht rückgängig gemacht werden.';
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
  String get sidebarBrowseData => 'Daten anzeigen';

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
  String get connectionMongoMode => 'Verbindungsmodus';

  @override
  String get connectionMongoModeDirect => 'Direkt (Einzelner Host)';

  @override
  String get connectionMongoModeReplicaSet => 'Replica Set';

  @override
  String get connectionMongoSeedHosts => 'Seed-Hosts';

  @override
  String get connectionMongoSeedHostsHint =>
      'Alle Replica-Set-Mitglieder auflisten (host:port, eins pro Zeile). Der Treiber erkennt das Primary automatisch; diese Liste ist maßgeblich.';

  @override
  String get connectionMongoSeedHostsRequired =>
      'Mindestens ein Seed-Host (host:port) ist erforderlich';

  @override
  String get connectionMongoReplicaSetName => 'Replica-Set-Name';

  @override
  String get connectionMongoReplicaSetNameRequired =>
      'Replica-Set-Name ist erforderlich';

  @override
  String get connectionMongoModeAdvanced =>
      'Erweitert (Verbindungszeichenfolge)';

  @override
  String get connectionMongoModeSharded => 'Sharded (mongos)';

  @override
  String get connectionMongoMongosHosts => 'mongos-Routen';

  @override
  String get connectionMongoMongosHostsHint =>
      'Alle mongos-Routenknoten auflisten (host:port, einer pro Zeile). Der Treiber verbindet sich über mongos; Sharding ist transparent.';

  @override
  String get connectionMongoMongosHostsRequired =>
      'Mindestens ein mongos-Router (host:port) ist erforderlich';

  @override
  String get connectionMongoInvalidHostPort =>
      'Ungültiger Eintrag (erwartet host oder host:port)';

  @override
  String get connectionMongoConnectionString => 'Verbindungszeichenfolge';

  @override
  String get connectionMongoConnectionStringHint =>
      'Vollständige Verbindungszeichenfolge einfügen (mongodb:// oder mongodb+srv://, inkl. Atlas). Anmeldedaten werden automatisch entfernt; das Passwort wird separat verschlüsselt gespeichert.';

  @override
  String get connectionMongoConnectionStringRequired =>
      'Bitte Verbindungszeichenfolge einfügen';

  @override
  String get connectionMongoConnectionStringInvalid =>
      'Ungültige Verbindungszeichenfolge (muss mit mongodb:// oder mongodb+srv:// beginnen)';

  @override
  String get connInvalidPort => 'Invalid port';

  @override
  String get connUsernameRequired => 'Benutzername ist erforderlich';

  @override
  String get connNameRequired => 'Verbindungsname ist erforderlich';

  @override
  String get connHostRequired => 'Host ist erforderlich';

  @override
  String get connPortRequired => 'Port ist erforderlich';

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
    return 'Löschen fehlgeschlagen: $error';
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
    return 'Are you sure you want to drop event \"$name\"?\n\nThis action cannot be undone.';
  }

  @override
  String sidebarEventOperationFailed(String error) {
    return 'Operation failed: $error';
  }

  @override
  String get sidebarEventNoDefinition => 'No definition';

  @override
  String get sidebarDropSynonym => 'Drop Synonym';

  @override
  String sidebarDropSynonymConfirm(String name) {
    return 'Are you sure you want to drop synonym \"$name\"?\n\nThis action cannot be undone.';
  }

  @override
  String sidebarSynonymOperationFailed(String error) {
    return 'Operation failed: $error';
  }

  @override
  String get sidebarEnableEvent => 'Enable Event';

  @override
  String get sidebarDisableEvent => 'Disable Event';

  @override
  String get sidebarEventProperties => 'Properties';

  @override
  String get sidebarSynonyms => 'Synonyms';

  @override
  String get sidebarBrowseSynonym => 'Browse Synonym';

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
  String get bottomPanelTabHistory => 'Verlauf';

  @override
  String get bottomPanelTabTasks => 'Aufgaben';

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
  String get dmlCriticalTitle => 'Kritische Operation';

  @override
  String get dmlHighWarningTitle => 'Risikoreiche Operation';

  @override
  String get dmlHighWarningBody =>
      'Dieser Vorgang betrifft alle übereinstimmenden Zeilen. Erwägen Sie eine LIMIT-Klausel.';

  @override
  String get dmlAddLimit => 'LIMIT hinzufügen';

  @override
  String get dmlConfirmExecute => 'Ausführung bestätigen';

  @override
  String get dmlRiskSummary => 'Risikoübersicht';

  @override
  String get dmlStatementsToExecute => 'Auszuführende Anweisungen:';

  @override
  String dmlEstimatedAffectedRows(Object count) {
    return 'Geschätzte betroffene Zeilen: $count';
  }

  @override
  String dmlSqlInjectionDetail(Object details) {
    return 'SQL-Injection: $details';
  }

  @override
  String get dmlTriggerDeleteWithoutWhere => 'DELETE ohne WHERE-Klausel';

  @override
  String get dmlTriggerUpdateWithoutWhere => 'UPDATE ohne WHERE-Klausel';

  @override
  String get dmlTriggerDropTable => 'DROP TABLE-Operation';

  @override
  String get dmlTriggerDropDatabase => 'DROP DATABASE-Operation';

  @override
  String get dmlTriggerTruncateTable => 'TRUNCATE TABLE-Operation';

  @override
  String get dmlTriggerDmlWithoutLimit => 'DML ohne LIMIT-Klausel';

  @override
  String get dmlTriggerAlterDropColumn => 'ALTER TABLE DROP COLUMN';

  @override
  String get dmlTriggerSqlInjection => 'SQL-Injection-Muster erkannt';

  @override
  String dropTableDeleteConfirmBody(Object tableName) {
    return 'Möchten Sie die Tabelle \"$tableName\" wirklich löschen?';
  }

  @override
  String get dropTableDeleteImpact =>
      'Dieser Vorgang kann nicht rückgängig gemacht werden. Alle Daten in der Tabelle werden dauerhaft gelöscht.';

  @override
  String get dropTableCheckingDependencies =>
      'Abhängigkeiten werden geprüft...';

  @override
  String get dropTableDependencyWarning => 'Abhängigkeitswarnung';

  @override
  String get connectionReadOnlyMode => 'Schreibgeschützter Modus';

  @override
  String get connectionReadOnlyModeDesc =>
      'INSERT/UPDATE/DELETE/DDL-Operationen verbieten';

  @override
  String get connectionSshHost => 'SSH-Host';

  @override
  String get connectionSshUsername => 'SSH-Benutzername';

  @override
  String get connectionSshPassword => 'SSH-Passwort';

  @override
  String get connSshHostRequired => 'SSH-Host ist erforderlich';

  @override
  String get commonNavigate => 'Navigieren';

  @override
  String get resultsSqlStatementLabel => 'SQL-Anweisung:';

  @override
  String get resultsExecutionSuccess => 'Ausführung erfolgreich';

  @override
  String resultsAffectedRows(Object count) {
    return '$count Zeilen betroffen';
  }

  @override
  String resultsElapsedMs(Object ms) {
    return 'Dauer: $ms ms';
  }

  @override
  String resultsFilterConditions(Object count) {
    return 'Filter: $count Bedingungen';
  }

  @override
  String resultsShowingRows(Object filtered, Object total) {
    return '$filtered / $total Zeilen angezeigt';
  }

  @override
  String get resultsClearFilter => 'Filter zurücksetzen';

  @override
  String get resultsNoDataGuidance =>
      'Schreiben Sie eine Abfrage im Editor und drücken Sie Strg+Eingabe (oder F5), um sie auszuführen';

  @override
  String get queryHistoryEmptyHint =>
      'Führen Sie eine Abfrage mit Strg+Eingabe oder F5 aus – sie erscheint dann automatisch hier';

  @override
  String get safetyExplainWarning => 'Leistungswarnung';

  @override
  String safetyExplainFullScan(Object rows) {
    return 'Vollständiger Tabellenscan erkannt. Geschätzte $rows Zeilen.';
  }

  @override
  String get safetyExecuteAnyway => 'Trotzdem ausführen';

  @override
  String get safetyCancelAndOptimize =>
      'Abbrechen und Ausführungsplan anzeigen';

  @override
  String get safetyPreflightTimeout =>
      'Vorabprüfung abgelaufen. Leistungsanalyse wird übersprungen.';

  @override
  String get dmlAuditBlocked => 'DML-Operation blockiert';

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
  String get processManagerTitle => 'Prozessmanager';

  @override
  String get processListNoProcesses => 'No active processes';

  @override
  String get processListNoQueryText => 'Kein Abfragetext';

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
  String get mongoNodeReplication => 'Replikation';

  @override
  String get mongoNodeSharding => 'Sharding';

  @override
  String get mongoValidationRules => 'Validierungsregeln';

  @override
  String get mongoReplicationStandalone =>
      'Stand-alone - kein Teil eines Replikatssets';

  @override
  String get mongoShardingNotSharded => 'Kein Sharding-Cluster';

  @override
  String get mongoValidationNoRules => 'Keine Validierungsregeln';

  @override
  String get resultColumnTruncated =>
      'Wert ist möglicherweise abgeschnitten (Large-Object-Typ)';

  @override
  String get dorisUpdateGuardMessage =>
      'Doris-Tabellen mit Duplicate-/Aggregate-Modell unterstützen kein UPDATE; nur Unique-/Primary-Key-Modelle.';

  @override
  String get dorisTableModelLabel => 'Tabellenmodell';

  @override
  String get dorisModelDuplicate => 'Duplicate';

  @override
  String get dorisModelUnique => 'Unique';

  @override
  String get dorisModelPrimaryKey => 'Primary Key';

  @override
  String get dorisHashColumnLabel => 'Hash-Spalte';

  @override
  String get dorisBucketsLabel => 'Buckets';

  @override
  String get dorisModelNeedsKeyColumn =>
      'Dieses Modell erfordert mindestens eine Schlüsselspalte (aktivieren Sie Primary Key für eine Spalte)';

  @override
  String get dorisAggregateFunctionLabel => 'Aggregatfunktion';

  @override
  String get dorisModelAggregate => 'Aggregate';

  @override
  String get dorisPartitionColumn => 'Partitionsspalte';

  @override
  String get dorisPartitionName => 'Partitionsname';

  @override
  String get dorisPartitionLessThan => 'Werte kleiner als';

  @override
  String get dorisAddPartition => 'Partition hinzufügen';

  @override
  String get offlineLicenseTitle => 'Offline-Lizenz';

  @override
  String get offlineLicensePurchaseHint =>
      'Zum Upgrade: Scannen Sie den Zahlungscode auf unserer GitHub/Gitee-Seite und senden Sie anschließend Ihren Maschinencode zusammen mit dem Zahlungs-Screenshot an den Autor. Sie erhalten eine Lizenz zum Importieren.';

  @override
  String get machineCodeLabel => 'Maschinencode';

  @override
  String get machineCodeUnavailable =>
      'Maschinencode kann auf diesem Gerät nicht gelesen werden';

  @override
  String get importLicense => 'Lizenz importieren';

  @override
  String get importLicenseHint =>
      'Lizenzzeichenfolge einfügen oder .dbmlicense-Datei wählen';

  @override
  String get buyLicense => 'Lizenz kaufen';

  @override
  String get machineCodeCopied => 'Maschinencode in die Zwischenablage kopiert';

  @override
  String get licenseFilePick => 'Datei wählen';

  @override
  String get licenseTypeYearly => 'Jahresabo';

  @override
  String get licenseTypeLifetime => 'Lifetime';

  @override
  String licenseExpiresAt(String date) {
    return 'Läuft ab: $date';
  }

  @override
  String get removeLicense => 'Lizenz entfernen';

  @override
  String get licenseImportSuccess =>
      'Lizenz aktiviert – Pro-Funktionen freigeschaltet';

  @override
  String get licenseErrorInvalid => 'Ungültiges Lizenzformat';

  @override
  String get licenseErrorSignature =>
      'Lizenzsignatur konnte nicht verifiziert werden';

  @override
  String get licenseErrorMachine =>
      'Diese Lizenz ist an ein anderes Gerät gebunden';

  @override
  String get licenseErrorExpired => 'Diese Lizenz ist abgelaufen';

  @override
  String get licenseErrorNoMachine =>
      'Maschinencode nicht lesbar; Offline-Lizenzierung auf diesem Gerät nicht verfügbar';

  @override
  String licenseActiveInfo(String email) {
    return 'Lizenziert für $email';
  }

  @override
  String get errorCopy => 'Kopieren';

  @override
  String get errorCopied => 'Kopiert';

  @override
  String get errorAnalyzeWithAi => 'Mit KI analysieren';

  @override
  String trialRemaining(int count, String feature) {
    return '$count Testnutzungen übrig für $feature';
  }

  @override
  String trialUsedUp(String feature) {
    return '$feature-Test aufgebraucht';
  }

  @override
  String get centerTitle => 'Ausführungszentrum';

  @override
  String get centerTabTasks => 'Aufgaben';

  @override
  String get centerTabErrors => 'Fehler';

  @override
  String get centerClearErrors => 'Fehler löschen';

  @override
  String get centerDismissError => 'Ausblenden';

  @override
  String get aiPromptErrorHeader =>
      'Diagnostiziere diesen Datenbankfehler: erkläre die Ursache und schlage eine Lösung vor.';

  @override
  String get commonUndo => 'Rückgängig';

  @override
  String commonDeleteWithCount(Object count) {
    return 'Löschen ($count)';
  }

  @override
  String aiPanelSessionsDeletedCount(Object count) {
    return '$count Unterhaltungen gelöscht';
  }

  @override
  String aiPanelSessionDeleted(Object title) {
    return '\"$title\" gelöscht';
  }

  @override
  String get aiPanelSelectDatabaseRequired =>
      'Bitte wählen Sie zuerst oben im Dropdown eine Datenbank aus.';

  @override
  String get aiPanelMongoExecutionPlan => '🔍 Mongo Ausführungsplan';

  @override
  String get aiPanelSelectSessions => 'Unterhaltungen auswählen';

  @override
  String get aiPanelExportTaskCreated => 'Export-Aufgabe erfolgreich erstellt';

  @override
  String get aiPanelDdlOperationCancelled =>
      'DDL-Vorgang vom Benutzer abgebrochen.';

  @override
  String get aiAssistantOpenTooltip => 'KI-Assistent öffnen';

  @override
  String get schemaImpactRiskLow => 'Niedriges Risiko';

  @override
  String get schemaImpactRiskMedium => 'Mittleres Risiko';

  @override
  String get schemaImpactRiskHigh => 'Hohes Risiko';

  @override
  String get schemaImpactRiskCritical => 'Kritisches Risiko';

  @override
  String get schemaImpactTitle => 'Schema-Auswirkungsanalyse';

  @override
  String schemaImpactSubtitle(Object table, Object type) {
    return '$type auf `$table`';
  }

  @override
  String get schemaImpactDataLossWarning =>
      'Datenverlustrisiko: Dieser Vorgang wird Daten endgültig löschen.';

  @override
  String schemaImpactAffectedObjects(Object count) {
    return 'Betroffene Objekte ($count)';
  }

  @override
  String schemaImpactWarnings(Object count) {
    return 'Warnungen ($count)';
  }

  @override
  String get schemaImpactRecommendations => 'Empfehlungen';

  @override
  String get schemaImpactHideRollbackScript => 'Rollback-Skript ausblenden';

  @override
  String get schemaImpactShowRollbackScript => 'Rollback-Skript anzeigen';

  @override
  String get schemaImpactNoRollbackAvailable => 'Kein Rollback verfügbar';

  @override
  String get schemaImpactRollbackCaveat =>
      'Auto-generiertes Rollback ist ein Best-Effort-Entwurf - Spaltentypen und Constraints können falsch sein. Vor der Ausführung prüfen; Daten sind nicht automatisch wiederherstellbar.';

  @override
  String get schemaImpactBackupRequired =>
      'Vor dem Rollback ist eine Datensicherung erforderlich';

  @override
  String get schemaImpactConfirmationRequired =>
      'Dieser Vorgang erfordert vor der Ausführung Ihre ausdrückliche Bestätigung.';

  @override
  String get ddlConfirmDialogTitle => 'DDL-Bestätigung erforderlich';

  @override
  String ddlAffectedObjectsCount(Object count) {
    return 'Betroffene Objekte ($count)';
  }

  @override
  String get ddlExecuteButton => 'DDL ausführen';

  @override
  String get ddlSqlStatementLabel => 'SQL-Anweisung:';

  @override
  String ddlRiskLevelLabel(Object level) {
    return 'Risikostufe: $level';
  }

  @override
  String get ddlDataLossRiskDetected => 'Datenverlustrisiko erkannt';

  @override
  String ddlWarningsCount(Object count) {
    return 'Warnungen ($count)';
  }

  @override
  String get ddlTypeConfirmationToProceed =>
      'Bestätigung eingeben, um fortzufahren';

  @override
  String ddlTypeToConfirmDestructive(Object token) {
    return '\"$token\" eingeben, um diesen destruktiven Vorgang zu bestätigen:';
  }

  @override
  String get commonUnknown => 'Unbekannt';

  @override
  String get commonDismiss => 'Schließen';

  @override
  String get readOnlyModeBlocked =>
      'Diese Verbindung ist schreibgeschützt; Schreibvorgänge sind deaktiviert.';

  @override
  String get dlgFillVariables => 'Variablen ausfüllen';

  @override
  String dlgVariableRequired(String variable) {
    return 'Bitte $variable eingeben';
  }

  @override
  String get dlgEditTrigger => 'Trigger bearbeiten';

  @override
  String get dlgCreateTrigger => 'Trigger erstellen';

  @override
  String triggerLoadTablesFailed(String error) {
    return 'Tabellen konnten nicht geladen werden: $error';
  }

  @override
  String get triggerSelectTableRequired => 'Bitte wählen Sie eine Tabelle';

  @override
  String get triggerSelectEventRequired =>
      'Bitte wählen Sie mindestens ein Ereignis';

  @override
  String get triggerUpdated => 'Trigger erfolgreich aktualisiert';

  @override
  String get triggerCreated => 'Trigger erfolgreich erstellt';

  @override
  String triggerSaveFailed(String error) {
    return 'Trigger konnte nicht gespeichert werden: $error';
  }

  @override
  String get triggerNameLabel => 'Trigger-Name';

  @override
  String get triggerNameRequired => 'Trigger-Name ist erforderlich';

  @override
  String get triggerNameInvalid => 'Ungültiges Format für Trigger-Namen';

  @override
  String get triggerTimingLabel => 'Zeitpunkt';

  @override
  String get triggerEventLabel => 'Ereignis';

  @override
  String get triggerTableLabel => 'Tabelle';

  @override
  String get triggerSelectTableHint => 'Tabelle auswählen';

  @override
  String get triggerBodyLabel => 'Trigger-Body';

  @override
  String get triggerBodyHint =>
      'Trigger-Body eingeben (SQL-Anweisungen)\nBeispiel:\nSET NEW.updated_at = NOW();';

  @override
  String triggerCount(int count) {
    return '$count Trigger';
  }

  @override
  String get dlgExecutionResult => 'Ausführungsergebnis';

  @override
  String dlgExecuteRoutine(String type) {
    return '$type ausführen';
  }

  @override
  String dlgRoutineName(String name) {
    return 'Name: $name';
  }

  @override
  String dlgRoutineType(String type) {
    return 'Typ: $type';
  }

  @override
  String dlgRoutineReturnType(String type) {
    return 'Rückgabetyp: $type';
  }

  @override
  String get dlgParameters => 'Parameter';

  @override
  String get dlgRoutineNoParams =>
      'Diese Prozedur/Funktion benötigt keine Parameter';

  @override
  String get dlgOutputParam => 'Ausgabeparameter';

  @override
  String get dlgReturnValueLabel => 'Rückgabewert:';

  @override
  String dlgRowsAffected(int count) {
    return 'Betroffene Zeilen: $count';
  }

  @override
  String dlgEditRoutine(String type) {
    return '$type bearbeiten';
  }

  @override
  String routineParameterCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Parameter',
      one: '1 Parameter',
      zero: 'Keine Parameter',
    );
    return '$_temp0';
  }

  @override
  String routineDeleteConfirmation(String type, String name) {
    return '$type \"$name\" löschen?';
  }

  @override
  String get routineListTitle => 'Prozeduren & Funktionen';

  @override
  String routineDefinitionTitle(String type) {
    return '$type Definition';
  }

  @override
  String get queryExecutionPlan => 'Abfrageausführungsplan';

  @override
  String dlgCreateRoutine(String type) {
    return '$type erstellen';
  }

  @override
  String get dlgNameRequired => 'Name ist erforderlich';

  @override
  String get dlgRoutineNameInvalid =>
      'Der Name darf nur Buchstaben, Ziffern und Unterstriche enthalten und nicht mit einer Ziffer beginnen';

  @override
  String get dlgReturnTypeRequired => 'Bitte wählen Sie einen Rückgabetyp';

  @override
  String get dlgSqlCode => 'SQL-Code';

  @override
  String get dlgRoutineProcedure => 'Gespeicherte Prozedur';

  @override
  String get dlgRoutineFunction => 'Funktion';

  @override
  String get commonUpdate => 'Aktualisieren';

  @override
  String get commonCreate => 'Erstellen';

  @override
  String get auditLogTitle => 'Abfrage-Auditprotokoll';

  @override
  String get auditLogAllStatus => 'Alle Status';

  @override
  String get auditLogAll => 'Alle';

  @override
  String get auditLogTime => 'Zeit';

  @override
  String get auditLogDuration => 'Dauer';

  @override
  String get auditLogRows => 'Zeilen';

  @override
  String get auditLogStatus => 'Status';

  @override
  String get auditLogEmpty => 'Noch keine Auditprotokolle';

  @override
  String get auditLogEmptyHint =>
      'Führen Sie Abfragen aus, um Protokolle aufzuzeichnen';

  @override
  String get auditLogTotal => 'Gesamt';

  @override
  String get auditLogWrite => 'Schreiben';

  @override
  String get auditLogAvgTime => 'Ø Zeit';

  @override
  String get auditLogClearTitle => 'Auditprotokolle löschen';

  @override
  String get auditLogClearConfirm =>
      'Möchten Sie wirklich alle Auditprotokolle löschen? Diese Aktion kann nicht rückgängig gemacht werden.';

  @override
  String get auditLogClear => 'Löschen';

  @override
  String get piiMaskingTitle => 'PII-Datenmaskierung';

  @override
  String get piiMaskingEnable => 'PII-Maskierung aktivieren';

  @override
  String get piiMaskingEnableDesc =>
      'Sensible Daten in Abfrageergebnissen automatisch maskieren';

  @override
  String get piiMaskingTypes => 'Sensible Datentypen';

  @override
  String get piiTypeEmail => 'E-Mail-Adressen';

  @override
  String get piiTypePhone => 'Telefonnummern';

  @override
  String get piiTypeIdCard => 'Ausweisnummern';

  @override
  String get piiTypeCreditCard => 'Kreditkarten';

  @override
  String get piiTypeBankCard => 'Bankkonten';

  @override
  String get piiTypePassword => 'Passwörter';

  @override
  String get piiTypeIpAddress => 'IP-Adressen';

  @override
  String get shortcutNoMatching => 'Keine passenden Tastenkürzel';

  @override
  String get shortcutPressEscToClose => 'Zum Schließen ESC drücken';

  @override
  String get indexTypePrimary => 'Primär';

  @override
  String get performanceAnalyzerWeeklyReportTitle =>
      'Wöchentliche Slow-Query-Berichte';

  @override
  String get performanceAnalyzerWeeklyReportDesc =>
      'Erhalten Sie jeden Montag die Top-10-Slow-Queries mit EXPLAIN-Analyse';

  @override
  String get performanceAnalyzerLearnMore => 'Mehr erfahren';

  @override
  String get backupListLoading => 'Sicherungsliste wird geladen...';

  @override
  String dbPropertiesTitle(String name) {
    return 'Datenbankeigenschaften - $name';
  }

  @override
  String get dbPropertyName => 'Name';

  @override
  String get dbPropertyCharset => 'Zeichensatz';

  @override
  String get dbPropertyCollation => 'Sortierregel';

  @override
  String get dbPropertySize => 'Größe';

  @override
  String get dbPropertyTableCount => 'Tabellen';

  @override
  String get dbPropertyViewCount => 'Sichten';

  @override
  String get dbPropertyRoutineCount => 'Prozeduren/Funktionen';

  @override
  String get exportFormatLabel => 'Exportformat';

  @override
  String exportRowCount(int count) {
    return '$count Zeilen gesamt';
  }

  @override
  String get taskCreateExportFilter => 'Filter';

  @override
  String get taskCreateExportEstRows => 'Geschätzte Zeilen';

  @override
  String get taskCreateExportValidating => 'Wird überprüft...';

  @override
  String get taskCreateExportSaveDialogTitle =>
      'Speicherort für Exportdatei auswählen';

  @override
  String taskValidationPathNotExists(String path) {
    return 'Verzeichnis existiert nicht: $path';
  }

  @override
  String taskCreateExportDesc(String table) {
    return '$table exportieren';
  }

  @override
  String taskCreateExportDescFiltered(String table) {
    return '$table exportieren (gefiltert)';
  }

  @override
  String get sqliteConnectionEditTitle => 'SQLite-Verbindung bearbeiten';

  @override
  String get sqliteConnectionNewTitle => 'Neue SQLite-Verbindung';

  @override
  String get createSuperTableTitle => 'Supertabelle erstellen';

  @override
  String get importWizardTitle => 'Datenimport-Assistent';

  @override
  String dbCreateSuccess(String name) {
    return 'Datenbank \"$name\" erfolgreich erstellt';
  }

  @override
  String get dbCreateFailed => 'Datenbank konnte nicht erstellt werden';

  @override
  String dbCreateError(String error) {
    return 'Fehler: $error';
  }

  @override
  String get dbOperationCannotBeUndone =>
      'Dieser Vorgang kann nicht rückgängig gemacht werden!';

  @override
  String dropTablePermanentWarning(String table) {
    return 'Tabelle \"$table\" und alle ihre Daten werden endgültig gelöscht.';
  }

  @override
  String get dropTableDataLossWarning =>
      'Dieser Vorgang kann nicht rückgängig gemacht werden! Alle Daten in dieser Tabelle gehen endgültig verloren.';

  @override
  String get objectTypeTable => 'Tabelle';

  @override
  String get objectTypeView => 'Sicht';

  @override
  String get commonRemove => 'Entfernen';

  @override
  String get commonRequired => 'Erforderlich';

  @override
  String get commonInvalidIdentifier => 'Ungültiger Bezeichner';

  @override
  String get mongoValidationJsonObject => 'JSON muss ein Objekt sein';

  @override
  String mongoValidationInvalidJson(String error) {
    return 'Ungültiges JSON: $error';
  }

  @override
  String get settingsAutoLimitEnabledDesc =>
      'SELECT-Abfragen automatisch LIMIT hinzufügen';

  @override
  String get sqliteConnectionInfo => 'Verbindungsinfo';

  @override
  String get sqliteNameHint => 'Meine SQLite-Datenbank';

  @override
  String get connectionDirNotExists => 'Verzeichnis existiert nicht';

  @override
  String get indexSelectColumnRequired =>
      'Bitte wählen Sie mindestens eine Spalte';

  @override
  String indexCreateFailed(String error) {
    return 'Index konnte nicht erstellt werden: $error';
  }

  @override
  String indexUpdateFailed(String error) {
    return 'Index konnte nicht aktualisiert werden: $error';
  }

  @override
  String get indexNameRequired => 'Indexname ist erforderlich';

  @override
  String get superTableTags => 'Tags';

  @override
  String get superTableCreated => 'Supertabelle erfolgreich erstellt';

  @override
  String get redisLibNameCodeRequired =>
      'Bibliotheksname und Code sind erforderlich';

  @override
  String get redisAdapterNotAvailable => 'Redis-Adapter nicht verfügbar';

  @override
  String get redisLibraryCreated => 'Funktionsbibliothek erfolgreich erstellt';

  @override
  String redisLibraryCreateFailed(String error) {
    return 'Bibliothek konnte nicht erstellt werden: $error';
  }

  @override
  String get redisLibraryUsageHint => 'Verwendet in #!lua name=<library>';

  @override
  String get redisInsertExample => 'Beispiel einfügen';

  @override
  String get redisCreateLibrary => 'Bibliothek erstellen';

  @override
  String redisKeyLoadFailed(String error) {
    return 'Schlüsseldaten konnten nicht geladen werden: $error';
  }

  @override
  String get redisKeyUpdated => 'Schlüssel erfolgreich aktualisiert';

  @override
  String redisKeySaveFailed(String error) {
    return 'Schlüssel konnte nicht gespeichert werden: $error';
  }

  @override
  String get redisKeySaveChanges => 'Änderungen speichern';

  @override
  String get serverConnectTitle => 'Mit Server verbinden';

  @override
  String get serverConnectUrl => 'Server-URL';

  @override
  String get serverUrlRequired => 'Server-URL ist erforderlich';

  @override
  String get serverUrlInvalid => 'Ungültige URL (z. B. https://myserver:3000)';

  @override
  String get serverConnectEmail => 'E-Mail';

  @override
  String get serverEmailRequired => 'E-Mail ist erforderlich';

  @override
  String get serverEmailInvalid => 'Ungültige E-Mail';

  @override
  String get serverPasswordRequired => 'Passwort ist erforderlich';

  @override
  String get mongoValidationFixErrors =>
      'Bitte beheben Sie die JSON-Fehler vor dem Anwenden';

  @override
  String get mongoValidationApplied =>
      'Validierungsregeln erfolgreich angewendet';

  @override
  String get mongoValidationRemoved => 'Validierungsregeln entfernt';

  @override
  String get mongoValidationLevel => 'Validierungsstufe';

  @override
  String get mongoValidationAction => 'Validierungsaktion';

  @override
  String mongoValidationApplyFailed(String error) {
    return 'Validierungsregeln konnten nicht angewendet werden: $error';
  }

  @override
  String get indexSelectColumns => 'Spalten auswählen';

  @override
  String get redisLibraryTitle => 'Funktionsbibliothek erstellen';

  @override
  String get redisLibraryNameLabel => 'Bibliotheksname';

  @override
  String get redisLibraryCreateFailedSyntax =>
      'Bibliothek konnte nicht erstellt werden (erfordert Redis 7.0+, Syntax prüfen)';

  @override
  String get redisLuaCodeLabel => 'Lua-Code';

  @override
  String get redisReplaceExisting =>
      'Vorhandene Bibliothek mit demselben Namen ersetzen (FUNCTION LOAD REPLACE)';

  @override
  String get redisLibraryInfoText =>
      'Der Bibliotheksname wird automatisch in den #!lua-Shebang geschrieben. Der Lua-Code sollte redis.register_function()-Aufrufe enthalten. Schreiben Sie den Shebang nicht selbst.';

  @override
  String get superTableCreateFailed =>
      'Supertabelle konnte nicht erstellt werden';

  @override
  String get superTableColumns => 'Spalten';

  @override
  String get errorTitle => 'Ein Fehler ist aufgetreten';

  @override
  String get errorDescriptionLabel => 'Fehlerdetails:';

  @override
  String get errorStackLabel => 'Stack-Trace:';

  @override
  String get columnFilterTypeNumeric => 'Numerisch';

  @override
  String get columnFilterTypeDateTime => 'Datum/Uhrzeit';

  @override
  String get columnFilterTypeText => 'Text';

  @override
  String get columnFilterPlaceholderNumeric => 'Zahl eingeben';

  @override
  String get columnFilterPlaceholderDateTime =>
      'Datum eingeben (z.B. 2024-01-01)';

  @override
  String get columnFilterPlaceholderText => 'Text eingeben';

  @override
  String columnFilterFor(String columnName) {
    return 'Filter: $columnName';
  }

  @override
  String columnFilterActive(int count) {
    return '$count aktive Filterbedingungen';
  }

  @override
  String columnFilterRowCount(String filtered, String total) {
    return '$filtered / $total Zeilen';
  }

  @override
  String get filterOpEquals => 'gleich';

  @override
  String get filterOpNotEquals => 'ungleich';

  @override
  String get filterOpContains => 'enthält';

  @override
  String get filterOpNotContains => 'enthält nicht';

  @override
  String get filterOpStartsWith => 'beginnt mit';

  @override
  String get filterOpEndsWith => 'endet mit';

  @override
  String get filterOpGreaterThan => 'größer als';

  @override
  String get filterOpGreaterThanOrEqual => 'größer oder gleich';

  @override
  String get filterOpLessThan => 'kleiner als';

  @override
  String get filterOpLessThanOrEqual => 'kleiner oder gleich';

  @override
  String get filterOpBetween => 'zwischen';

  @override
  String get filterOpIsNull => 'ist null';

  @override
  String get filterOpIsNotNull => 'ist nicht null';

  @override
  String get filterOpIsEmpty => 'ist leer';

  @override
  String get filterOpIsNotEmpty => 'ist nicht leer';

  @override
  String get tableNoData => 'Keine Daten';

  @override
  String tableRowCountTotal(String count) {
    return '$count Zeilen insgesamt';
  }

  @override
  String get tableLargeDatasetHint => '(Großer Datensatz, zum Laden scrollen)';

  @override
  String tableRowRange(String start, String end, String total) {
    return '$start-$end / $total Zeilen';
  }

  @override
  String get importWizStepSelectFile => 'Datei auswählen';

  @override
  String get importWizStepAnalyzeFile => 'Datei analysieren';

  @override
  String get importWizStepColumnMapping => 'Spaltenzuordnung';

  @override
  String get importWizStepPreviewPII => 'Vorschau & PII';

  @override
  String get importWizStepConfirmImport => 'Import bestätigen';

  @override
  String importWizStepOf(String current, String total, String title) {
    return 'Schritt $current von $total: $title';
  }

  @override
  String get importWizTargetDatabase => 'Zieldatenbank';

  @override
  String get importWizSelectDatabase => 'Datenbank auswählen';

  @override
  String get importWizTargetTableOptional => 'Zieltabelle (optional)';

  @override
  String get importWizLetAiInfer => '-- KI Tabellennamen ableiten lassen --';

  @override
  String get importWizChooseFile => 'Zum Auswählen klicken oder hierher ziehen';

  @override
  String get importWizChangeFile => 'Datei wechseln';

  @override
  String get importWizSupportedFormats =>
      'Unterstützt CSV, JSON, Excel, TSV-Formate';

  @override
  String get importWizFileUnknown => 'Unbekannt';

  @override
  String get importWizAiAnalyzing => 'KI analysiert die Datei...';

  @override
  String get importWizDetectingFormat =>
      'Erkennt Format, Kodierung, Feldtypen...';

  @override
  String get importWizFileAnalysisResult => 'Dateianalyse-Ergebnis';

  @override
  String get importWizFormat => 'Format';

  @override
  String get importWizEncoding => 'Kodierung';

  @override
  String get importWizFieldCount => 'Felder';

  @override
  String get importWizEstimatedRows => 'Gesch. Zeilen';

  @override
  String get importWizFileSize => 'Dateigröße';

  @override
  String get importWizDelimiter => 'Trennzeichen';

  @override
  String get importWizDetectedFields => 'Erkannte Felder';

  @override
  String get importWizAiSuggestion => 'KI-Vorschlag';

  @override
  String importWizTargetTableName(String tableName) {
    return 'Zieltabelle: $tableName';
  }

  @override
  String get importWizNoAnalysisResult => 'Kein Analyseergebnis';

  @override
  String get importWizSelectFileFirst =>
      'Bitte wählen Sie zuerst eine Datei aus';

  @override
  String get importWizNoColumnMapping => 'Keine Spaltenzuordnung';

  @override
  String get importWizGeneratingMapping => 'Generiere Zuordnung...';

  @override
  String get importWizColumnMappingConfig => 'Spaltenzuordnung-Konfiguration';

  @override
  String importWizColumnsMapped(String mapped, String total) {
    return '$mapped/$total Spalten zugeordnet';
  }

  @override
  String get importWizMappingDescription =>
      'Ordnen Sie Dateispalten den Datenbanktabellenspalten zu. Wählen Sie \"Überspringen\", um eine Spalte zu überspringen.';

  @override
  String get importWizFileColumn => 'Dateispalte';

  @override
  String get importWizDatabaseColumn => 'Datenbankspalte';

  @override
  String get importWizType => 'Typ';

  @override
  String get importWizPiiDetection => 'PII-Erkennung sensibler Daten';

  @override
  String get importWizPiiDetectionMessage =>
      'Die folgenden sensiblen Felder wurden erkannt. Bitte bestätigen Sie, ob der Import fortgesetzt werden soll:';

  @override
  String get importWizPiiAcknowledge => 'Ich verstehe, Import fortsetzen';

  @override
  String get importWizDataPreview => 'Datenvorschau';

  @override
  String importWizWarnings(String count) {
    return '$count Warnungen';
  }

  @override
  String importWizFirstRows(String count) {
    return 'Erste $count Zeilen';
  }

  @override
  String get importWizSensitiveField => 'Sensibles Feld';

  @override
  String get importWizDataValidationWarnings => 'Datenvalidierungswarnungen';

  @override
  String importWizValidationRowFormat(String row, String col, String msg) {
    return 'Zeile $row, Spalte $col: $msg';
  }

  @override
  String get importWizImportSummary => 'Import-Konfigurationsübersicht';

  @override
  String get importWizSummaryTargetDatabase => 'Zieldatenbank';

  @override
  String get importWizSummaryTargetTable => 'Zieltabelle';

  @override
  String get importWizSummaryFile => 'Datei';

  @override
  String get importWizSummaryMappedColumns => 'Zugeordnete Spalten';

  @override
  String get importWizSummaryDataRows => 'Datenzeilen';

  @override
  String get importWizConflictStrategy => 'Konfliktlösungsstrategie';

  @override
  String get importWizConflictSkip => 'Duplikate überspringen';

  @override
  String get importWizConflictSkipDesc =>
      'Wenn ein doppelter Schlüssel gefunden wird, die Zeile überspringen und mit dem Import fortfahren';

  @override
  String get importWizConflictUpdate => 'Vorhandene Zeilen aktualisieren';

  @override
  String get importWizConflictUpdateDesc =>
      'Wenn ein doppelter Schlüssel gefunden wird, die vorhandenen Daten aktualisieren';

  @override
  String get importWizConflictAbort => 'Import abbrechen';

  @override
  String get importWizConflictAbortDesc =>
      'Wenn ein doppelter Schlüssel gefunden wird, den Import sofort stoppen';

  @override
  String get importWizConflictSkipName => 'Duplikate überspringen';

  @override
  String get importWizConflictUpdateName => 'Vorhandene aktualisieren';

  @override
  String get importWizConflictAbortName => 'Abbrechen';

  @override
  String get importWizImporting => 'Importiere...';

  @override
  String importWizRowsProgress(String imported, String total) {
    return '$imported/$total Zeilen';
  }

  @override
  String importWizFailedRows(String count) {
    return 'Fehlgeschlagen: $count Zeilen';
  }

  @override
  String get importWizImportComplete => 'Import abgeschlossen!';

  @override
  String importWizImportFailed(String error) {
    return 'Import fehlgeschlagen: $error';
  }

  @override
  String importWizImportSuccessMsg(String count) {
    return 'Erfolgreich $count Zeilen importiert';
  }

  @override
  String get importWizImportErrorMsg =>
      'Beim Import ist ein Fehler aufgetreten';

  @override
  String get importWizPreviousStep => 'Zurück';

  @override
  String get importWizClose => 'Schließen';

  @override
  String get importWizStartImport => 'Import starten';

  @override
  String get importWizNextStep => 'Weiter';

  @override
  String get importWizReimport => 'Erneut importieren';

  @override
  String importWizLoadDatabasesFailed(String error) {
    return 'Fehler beim Laden der Datenbankliste: $error';
  }

  @override
  String importWizLoadTablesFailed(String error) {
    return 'Fehler beim Laden der Tabellenliste: $error';
  }

  @override
  String importWizPickFileFailed(String error) {
    return 'Fehler beim Auswählen der Datei: $error';
  }

  @override
  String importWizAnalysisFailed(String error) {
    return 'Analyse fehlgeschlagen: $error';
  }

  @override
  String importWizMappingFailed(String error) {
    return 'Fehler beim Erstellen der Spaltenzuordnung: $error';
  }

  @override
  String get importWizFileAnalysisFailed => 'Dateianalyse fehlgeschlagen';

  @override
  String get importWizImportFailedGeneric => 'Import fehlgeschlagen';

  @override
  String get importWizNotSelected => 'Nicht ausgewählt';

  @override
  String get importWizNotSet => 'Nicht festgelegt';

  @override
  String get importWizUnknown => 'Unbekannt';

  @override
  String get importWizPiiDetectionSummary => 'PII-Erkennung';

  @override
  String importWizSensitiveFieldCount(String count) {
    return '$count sensible Felder';
  }

  @override
  String get smartImportAnalyzingDetail =>
      'KI identifiziert Feldtypen und generiert CREATE TABLE-Anweisung';

  @override
  String get smartImportColumnMapping => 'Spaltenzuordnung';

  @override
  String smartImportColumnsMapped(String mapped, String total) {
    return '$mapped/$total Spalten zugeordnet';
  }

  @override
  String get smartImportFileColumn => 'Dateispalte';

  @override
  String get smartImportTableColumn => 'Tabellenspalte';

  @override
  String get smartImportConflictResolution => 'Konfliktlösung';

  @override
  String get smartImportDataPreview => 'Datenvorschau';

  @override
  String smartImportFirstRows(String count) {
    return 'Erste $count Zeilen';
  }

  @override
  String get smartImportBack => 'Zurück';

  @override
  String get smartImportBackgroundTask => 'Hintergrundimport';

  @override
  String get smartImportFailedToGenerateSql =>
      '-- CREATE TABLE-Anweisung konnte nicht generiert werden';

  @override
  String smartImportTargetTableSelected(String table) {
    return 'Zieltabelle ausgewählt: $table';
  }

  @override
  String smartImportTargetTableEntered(String table) {
    return 'Zieltabelle eingegeben: $table';
  }

  @override
  String smartImportAnalysisFailed(String error) {
    return 'Dateianalyse fehlgeschlagen: $error';
  }

  @override
  String smartImportColumnMappingsComplete(String mapped, String total) {
    return 'Spaltenzuordnung abgeschlossen: $mapped/$total Spalten automatisch zugeordnet';
  }

  @override
  String smartImportPiiDetected(String types) {
    return 'PII-Erkennung: Sensible Felder gefunden - $types';
  }

  @override
  String get smartImportPiiNone =>
      'PII-Erkennung: Keine sensiblen Felder gefunden';

  @override
  String smartImportPiiFailed(String error) {
    return 'PII-Erkennung fehlgeschlagen: $error';
  }

  @override
  String smartImportPreviewGenerated(String count) {
    return 'Datenvorschau generiert ($count Zeilen)';
  }

  @override
  String smartImportPreviewFailed(String error) {
    return 'Fehler beim Generieren der Vorschau: $error';
  }

  @override
  String smartImportMappingFailed(String error) {
    return 'Fehler beim Generieren der Spaltenzuordnung: $error';
  }

  @override
  String importServiceStartImport(String table) {
    return 'Starte Datenimport in Tabelle \"$table\"...';
  }

  @override
  String importServiceColumnMapping(String mapped, String total) {
    return 'Spaltenzuordnung: $mapped/$total Spalten zugeordnet';
  }

  @override
  String importServiceConflictStrategy(String strategy) {
    return 'Konfliktlösungsstrategie: $strategy';
  }

  @override
  String get importServiceImporting => 'Starte Datenimport...';

  @override
  String importServiceBatchSuccess(String batch, String count) {
    return 'Stapel $batch: $count Zeilen erfolgreich importiert';
  }

  @override
  String importServiceBatchInsertFailed(String count) {
    return 'Stapelimport fehlgeschlagen ($count Zeilen), versuche zeilenweise...';
  }

  @override
  String importServiceUpdateFailed(String error) {
    return 'Aktualisierung fehlgeschlagen: $error';
  }

  @override
  String importServiceDataTooLong(String row) {
    return 'Zeile $row Daten zu lang, übersprungen';
  }

  @override
  String importServiceRowInsertFailed(String row, String error) {
    return 'Zeile $row Import fehlgeschlagen: $error';
  }

  @override
  String importServiceBatchSkipped(String count) {
    return 'Stapel übersprungen: $count Zeilen (Duplikate)';
  }

  @override
  String importServiceBatchUpdated(String count) {
    return 'Stapel aktualisiert: $count Zeilen';
  }

  @override
  String importServiceBatchFailed(String count) {
    return 'Stapel fehlgeschlagen: $count Zeilen';
  }

  @override
  String importServicePhaseProgress(
    String imported,
    String skipped,
    String updated,
  ) {
    return '$imported Zeilen importiert, $skipped übersprungen, $updated aktualisiert...';
  }

  @override
  String get importServiceImportCancelled => 'Import abgebrochen';

  @override
  String importServiceFileReadFailed(String error) {
    return 'Datei konnte nicht gelesen werden: $error';
  }

  @override
  String importServiceImportComplete(String imported, String failed) {
    return 'Import abgeschlossen! Erfolg: $imported Zeilen, Fehlgeschlagen: $failed Zeilen';
  }

  @override
  String taskExecutorAnalyzeFile(String path) {
    return 'Analysiere Datei: $path';
  }

  @override
  String taskExecutorFileFormat(String format, String encoding, String rows) {
    return 'Dateiformat: $format, Kodierung: $encoding, Geschätzte Zeilen: $rows';
  }

  @override
  String get taskExecutorTableNotExists =>
      'Tabelle existiert nicht, wird erstellt...';

  @override
  String get taskExecutorTableCreated => 'Tabelle erfolgreich erstellt';

  @override
  String get taskExecutorTableCreateFailed =>
      'Fehler beim Erstellen der Tabelle';

  @override
  String taskExecutorTableNotExistsError(String table) {
    return 'Zieltabelle \"$table\" existiert nicht. Bitte erstellen Sie die Tabelle zuerst.';
  }

  @override
  String get taskExecutorNoColumnMapping =>
      'Keine verwendbare Spaltenzuordnung. Bitte überprüfen Sie, ob die Dateifelder mit den Tabellenfeldern übereinstimmen.';

  @override
  String taskExecutorColumnMapping(String mapped, String total) {
    return 'Spaltenzuordnung: $mapped/$total Spalten zugeordnet';
  }

  @override
  String get taskExecutorStartImport => 'Starte Datenimport...';

  @override
  String taskExecutorImportComplete(String imported, String failed) {
    return 'Import abgeschlossen! Erfolg: $imported Zeilen, Fehlgeschlagen: $failed Zeilen';
  }

  @override
  String get taskExecutorImportFinished => 'Import abgeschlossen';

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
  String get viewModeTable => 'Tabelle';

  @override
  String get viewModeChart => 'Diagramm';

  @override
  String get viewModeCard => 'Karte';

  @override
  String get viewModeDocument => 'Dokumente';

  @override
  String get viewModeJsonTree => 'JSON-Baum';

  @override
  String get viewModeKeyValue => 'Schlüssel-Werte';

  @override
  String get documentExpand => 'Ausklappen';

  @override
  String get documentCollapse => 'Einklappen';

  @override
  String documentExpandMore(int count) {
    return '$count weitere Felder ausklappen';
  }

  @override
  String jsonTreeItemCount(int count) {
    return '$count Einträge';
  }

  @override
  String get keyValueField => 'Feld';

  @override
  String get keyValueValue => 'Wert';

  @override
  String keyValueFieldLabel(String field) {
    return 'Feld: $field';
  }

  @override
  String keyValueLengthLabel(int length) {
    return 'Länge: $length Zeichen';
  }

  @override
  String get chartViewComingSoon => 'Diagrammansicht (bald)';

  @override
  String chartExportSuccess(String path) {
    return 'Diagramm gespeichert unter $path';
  }

  @override
  String chartExportFailed(String error) {
    return 'Diagrammexport fehlgeschlagen: $error';
  }

  @override
  String chartSamplingNotice(int count) {
    return 'Großer Datensatz: $count Punkte für Leistung abgetastet';
  }

  @override
  String get chartAiTrend => 'KI-Trendanalyse';

  @override
  String get chartTypeLine => 'Linie';

  @override
  String get chartTypeBar => 'Balken';

  @override
  String get chartTypePie => 'Torte';

  @override
  String get chartTypeScatter => 'Streuung';

  @override
  String get statisticsPanelTitle => 'Statistik';

  @override
  String get exportStepBack => 'Zurück';

  @override
  String get exportStepNext => 'Weiter';

  @override
  String get noJsonDataToSample => 'Keine Daten zum Stichproben';

  @override
  String get noLeafNodes => 'Keine extrahierbaren Felder';

  @override
  String get fieldNotInAllRows => 'nicht in allen Zeilen';

  @override
  String get commonRetry => 'Wiederholen';

  @override
  String get extensionNoAdapter => 'Kein Adapter';

  @override
  String get extensionNotPostgres => 'Keine PostgreSQL-Verbindung';

  @override
  String get extensionLoadFailed => 'Mitglieder konnten nicht geladen werden';

  @override
  String get extensionTypes => 'Typen';

  @override
  String get extensionFunctions => 'Funktionen';

  @override
  String get extensionOperators => 'Operatoren';

  @override
  String get extensionSchema => 'Schema';

  @override
  String get extensionDescription => 'Beschreibung';

  @override
  String get vectorLoadFailed => 'Vektorindizes konnten nicht geladen werden';

  @override
  String get vectorNoAdapter => 'Kein Adapter';

  @override
  String get vectorNoIndexes => 'Keine Vektorindizes definiert';

  @override
  String get jsonInvalidJson => 'Ungultiges JSON';

  @override
  String get jsonNoMatches => 'Keine Treffer';

  @override
  String get jsonSearchHint => 'Schlussel oder Werte suchen...';

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
  String get mcpTokensMenuLabel => 'MCP-Token';

  @override
  String get mcpTokensTitle => 'MCP-Token';

  @override
  String get mcpTokensIntro =>
      'Langlebige Token für KI-Clients (Claude Code, Cursor). Fügen Sie einen als Bearer-Token in die MCP-Konfiguration des Clients ein; jederzeit widerrufbar.';

  @override
  String get mcpTokensNotConnected =>
      'Verbinden Sie sich mit einem DbMaster-Server, um MCP-Token zu verwalten.';

  @override
  String get mcpTokensEmpty =>
      'Noch keine Token. Erstellen Sie einen für Ihren KI-Client.';

  @override
  String get mcpTokensNameHint => 'Token-Name (z. B. claude-code-mac)';

  @override
  String get mcpTokensCreate => 'Erstellen';

  @override
  String mcpTokensOnceTitle(String name) {
    return 'Token „$name“ erstellt';
  }

  @override
  String get mcpTokensOnceWarning =>
      'Kopieren Sie ihn jetzt — aus Sicherheitsgründen wird er nie wieder angezeigt. Verwenden Sie ihn als Bearer-Token in Ihrer MCP-Client-Konfiguration (z. B. mcp.json).';

  @override
  String get mcpTokensCopy => 'Kopieren';

  @override
  String get mcpTokensCopied => 'Token in die Zwischenablage kopiert';

  @override
  String get mcpTokensDone => 'Fertig';

  @override
  String mcpTokensLastUsed(String value) {
    return 'Zuletzt verwendet: $value';
  }

  @override
  String get mcpTokensNeverUsed => 'nie';

  @override
  String get mcpTokensRevoke => 'Widerrufen';

  @override
  String get mcpTokensRevokeTitle => 'Dieses Token widerrufen?';

  @override
  String mcpTokensRevokeBody(String name, String prefix) {
    return 'Clients, die „$name“ ($prefix…) verwenden, funktionieren sofort nicht mehr. Dies kann nicht rückgängig gemacht werden.';
  }

  @override
  String get serverConnectionsMenuLabel => 'Server-Verbindungen';

  @override
  String get serverConnectionsTitle => 'Server-Verbindungen';

  @override
  String get serverConnectionsIntro =>
      'Auf dem Server registrierte Datenbankverbindungen. Datensynchronisierung, Health-Checks und DDL-Freigaben laufen gegen diese; die Desktop-Seitenleiste ist davon getrennt.';

  @override
  String get serverConnectionsNotConnected =>
      'Nicht mit einem Server verbunden.';

  @override
  String get serverConnectionsEmpty =>
      'Noch keine Server-Verbindungen. Fügen Sie eine hinzu, damit Datensynchronisierung / Health-Check / Freigabe-Aufgaben eine Datenbank haben.';

  @override
  String get serverConnectionsAdd => 'Hinzufügen';

  @override
  String get serverConnectionsEdit => 'Bearbeiten';

  @override
  String get serverConnectionsDelete => 'Löschen';

  @override
  String get serverConnectionsKindCollab => 'Kollab';

  @override
  String get serverConnectionsKindSourceDrift =>
      'Drift-Quelle (schreibgeschützt)';

  @override
  String get serverConnectionsDeleteTitle => 'Verbindung löschen';

  @override
  String serverConnectionsDeleteBody(String name) {
    return 'Server-Verbindung „$name“ löschen?';
  }

  @override
  String serverConnectionsDeleteTaskWarning(num count) {
    return '$count Aufgabe(n) verweisen auf diese Verbindung und werden gelöscht (als Quelle) oder getrennt (als Ziel).';
  }

  @override
  String get serverConnFormCreateTitle => 'Server-Verbindung hinzufügen';

  @override
  String get serverConnFormEditTitle => 'Server-Verbindung bearbeiten';

  @override
  String get serverConnFormName => 'Name';

  @override
  String get serverConnFormType => 'Typ';

  @override
  String get serverConnFormHost => 'Host';

  @override
  String get serverConnFormPort => 'Port';

  @override
  String get serverConnFormUsername => 'Benutzername';

  @override
  String get serverConnFormPassword => 'Passwort';

  @override
  String get serverConnFormPasswordKeepHint =>
      'Leer lassen, um das gespeicherte Passwort beizubehalten';

  @override
  String get serverConnFormDatabase => 'Standarddatenbank (optional)';

  @override
  String get serverConnFormSqlitePath => 'Datenbankdateipfad';

  @override
  String get serverConnFormSave => 'Speichern';

  @override
  String get serverConnFormRequired => 'Pflichtfeld';

  @override
  String get serverConnFormInvalidPort => 'Port muss eine Zahl sein';

  @override
  String get dataSyncConnectionNotOnServer =>
      'Die ausgewählte Verbindung ist auf dem Server nicht registriert. Fügen Sie sie zuerst unter „Server-Verbindungen“ hinzu und versuchen Sie es erneut.';

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
    return 'Bereitgestellt von $plugin';
  }

  @override
  String get connectionDbIndex => 'Datenbank-Index';

  @override
  String get connectionAuthDatabase => 'Authentifizierungsdatenbank';

  @override
  String get connectionRedisAuthNone => 'Keine Authentifizierung';

  @override
  String get connectionRedisAuthNoneDesc =>
      'Keine Authentifizierung erforderlich';

  @override
  String get connectionRedisAuthPasswordOnly => 'Nur Passwort';

  @override
  String get connectionRedisAuthPasswordOnlyDesc =>
      'AUTH-Passwort (Redis < 6.0)';

  @override
  String get connectionRedisAuthUsernamePassword =>
      'Benutzername + Passwort (ACL)';

  @override
  String get connectionRedisAuthUsernamePasswordDesc =>
      'AUTH Benutzername Passwort (Redis 6.0+ ACL)';

  @override
  String get connectionSshAuthPassword => 'Passwort';

  @override
  String get connectionSshAuthPrivateKey => 'Privater Schlüssel';

  @override
  String get sidebarCapabilityTitle => 'Funktionen';

  @override
  String get sidebarCapGroupDatabaseObjects => 'Datenbankobjekte';

  @override
  String get sidebarCapGroupAdvanced => 'Erweitert';

  @override
  String get redisCapGroupKeyspace => 'Keyspace';

  @override
  String get redisCapWorkbench => 'Befehlszeile-Workbench';

  @override
  String get redisCapPubsub => 'Pub/Sub';

  @override
  String get redisCapLua => 'Lua-Skripte';

  @override
  String get redisCapPipeline => 'Pipeline';

  @override
  String get redisCapTransaction => 'Transaktion';

  @override
  String get redisCapMemoryAnalysis => 'Speicheranalyse';

  @override
  String get redisCapKeyspaceNotifications => 'Keyspace-Benachrichtigungen';

  @override
  String get redisCapAcl => 'ACL-Verwaltung';

  @override
  String get redisCapConfig => 'Konfiguration bearbeiten';

  @override
  String get mongoValidationTitle => 'Validierungsregeln';

  @override
  String get mongoValidationNoValidator =>
      'Für diese Collection sind keine Validierungsregeln konfiguriert (über collMod oder die MongoDB-Shell hinzufügen).';

  @override
  String mongoValidationLoadFailed(String error) {
    return 'Validierungsregeln konnten nicht geladen werden: $error';
  }

  @override
  String sidebarDocumentInserted(String collection) {
    return 'Dokument in $collection eingefügt';
  }

  @override
  String get aiSkillCatalogTitle => 'Fähigkeiten';

  @override
  String get aiSkillGroupSql => 'SQL';

  @override
  String get aiSkillGroupData => 'Daten';

  @override
  String get aiSkillGroupSchema => 'Schema';

  @override
  String get aiSkillGroupOps => 'Betrieb';

  @override
  String get aiSkillNl2sqlName => 'Natürliche Sprache zu SQL';

  @override
  String get aiSkillNl2sqlDesc => 'Beschreibe, was du willst, und erhalte SQL';

  @override
  String get aiSkillSqlExplainName => 'SQL-Erklärung';

  @override
  String get aiSkillSqlExplainDesc => 'Erkläre, was eine SQL-Anweisung tut';

  @override
  String get aiSkillSqlExplainPrompt =>
      'Erkläre Schritt für Schritt, was diese SQL-Anweisung tut:\n```\n\n```';

  @override
  String get aiSkillQueryOptimizerName => 'Abfrageoptimierung';

  @override
  String get aiSkillQueryOptimizerDesc =>
      'Analysiere eine langsame Abfrage und schlage Optimierungen vor';

  @override
  String get aiSkillQueryOptimizerPrompt =>
      'Analysiere diese Abfrage auf Leistungsprobleme und schlage Optimierungen vor:\n```\n\n```';

  @override
  String get aiSkillDataCleaningName => 'Datenbereinigung';

  @override
  String get aiSkillDataCleaningDesc =>
      'Schlage Schritte zur Bereinigung schmutziger Daten vor';

  @override
  String get aiSkillDataCleaningPrompt =>
      'Schlage Bereinigungsschritte für schmutzige Daten in meiner Tabelle vor. Bekannte Probleme:';

  @override
  String get aiSkillImportMappingName => 'Import-Mapping';

  @override
  String get aiSkillImportMappingDesc =>
      'Erzeuge ein Spalten-Mapping für den Datenimport';

  @override
  String get aiSkillImportMappingPrompt =>
      'Erzeuge ein Spalten-Mapping (JSON), um die folgende Datei in die Tabelle zu importieren.\nQuellspalten:\nZielspalten:';

  @override
  String get aiSkillSchemaAnalysisName => 'Schema-Analyse';

  @override
  String get aiSkillSchemaAnalysisDesc =>
      'Prüfe das aktuelle Schema und weise auf Risiken hin';

  @override
  String get aiSkillSchemaAnalysisPrompt =>
      'Prüfe das aktuelle Datenbankschema und weise auf Designrisiken und Verbesserungen hin.';

  @override
  String get aiSkillSchemaDiffName => 'Schema-Diff-Assistent';

  @override
  String get aiSkillSchemaDiffDesc =>
      'Vergleiche zwei Schema-Definitionen und erzeuge ein Diff';

  @override
  String get aiSkillSchemaDiffPrompt =>
      'Vergleiche die folgenden beiden Schema-Definitionen und erzeuge ein Unified Diff:\n<schema-a>\n\n</schema-a>\n<schema-b>\n\n</schema-b>';

  @override
  String get aiSkillIndexSuggestName => 'Index-Empfehlungen';

  @override
  String get aiSkillIndexSuggestDesc =>
      'Schlage Indizes für eine Abfrage oder Tabelle vor';

  @override
  String get aiSkillIndexSuggestPrompt =>
      'Schlage Indizes für diese Abfrage vor und begründe sie:\n```\n\n```';

  @override
  String get aiSkillErrorDiagnosisName => 'Fehlerdiagnose';

  @override
  String get aiSkillErrorDiagnosisDesc =>
      'Diagnostiziere eine Datenbankfehlermeldung';

  @override
  String get aiSkillErrorDiagnosisPrompt =>
      'Diagnostiziere diesen Datenbankfehler und schlage Fixes vor:\n```\n\n```';

  @override
  String get aiSkillSlowQueryName => 'Slow-Query-Analyse';

  @override
  String get aiSkillSlowQueryDesc => 'Analysiere Slow-Query-Log-Einträge';

  @override
  String get aiSkillSlowQueryPrompt =>
      'Analysiere diesen Slow-Query-Log-Eintrag und lokalisiere den Flaschenhals:\n```\n\n```';

  @override
  String get aiContextPanelTitle => 'Kontext';

  @override
  String get aiContextConnectionSection => 'Aktuelle Verbindung';

  @override
  String get aiContextDatabaseSection => 'Aktuelle Datenbank';

  @override
  String get aiContextNoConnection => 'Keine Verbindung ausgewählt';

  @override
  String get aiContextSchemaContext => 'Schema-Kontext anhängen';

  @override
  String get aiContextSchemaContextDesc =>
      'Beim Senden Tabellenschemata der aktuellen Datenbank anhängen';

  @override
  String get aiPanelOpenSkillCatalog => 'Fähigkeiten-Katalog';

  @override
  String get aiPanelOpenContextPanel => 'Kontext-Panel';

  @override
  String get safetyBannerAddLimit => 'LIMIT hinzufügen';

  @override
  String safetyBannerCooldown(int seconds) {
    return 'Bestätigen (${seconds}s)';
  }

  @override
  String get safetyDmlAllRowsWarning =>
      'Dieser Vorgang betrifft alle übereinstimmenden Zeilen. Erwägen Sie eine LIMIT-Klausel.';

  @override
  String get safetySeverityHigh => 'Hoch';

  @override
  String get safetySeverityMedium => 'Warnung';

  @override
  String get safetySeverityLow => 'Info';

  @override
  String get safetySeverityPolicy => 'Richtlinie';

  @override
  String gateTitleSingle(int count) {
    return 'Ausführungsbestätigung: $count Risiko(s) in dieser SQL';
  }

  @override
  String gateTitleMulti(int count, int total) {
    return 'Ausführungsbestätigung: $count Risiko(s) in $total Anweisungen';
  }

  @override
  String get gateDdlImpactTitle => 'DDL-Auswirkungsanalyse';

  @override
  String gateStatementLabel(int n) {
    return 'Anweisung $n';
  }

  @override
  String get gateSuggestionLabel => 'Vorgeschlagene Korrektur';

  @override
  String gateOverview(int total, int high, int medium, int low, int ok) {
    return '$total Anweisungen · Hoch $high · Warnung $medium · Info $low · OK $ok';
  }

  @override
  String gateSkipHighRisk(int skip, int exec) {
    return '$skip mit hohem Risiko überspringen, $exec ausführen';
  }

  @override
  String get gateAllHighDisabled =>
      'Alle mit hohem Risiko — nichts auszuführen';

  @override
  String get gateApplySuggestions => 'Vorschläge übernehmen';

  @override
  String get gateProceed => 'Trotzdem ausführen';

  @override
  String get gateProceedAll => 'Alle trotzdem ausführen';

  @override
  String get gateCancelAll => 'Alle abbrechen';

  @override
  String get settingsNavAppearance => 'Erscheinungsbild';

  @override
  String get settingsNavAi => 'KI';

  @override
  String get settingsNavQuery => 'Abfragen';

  @override
  String get settingsNavLanguage => 'Sprache';

  @override
  String get settingsNavSecurity => 'Sicherheit';

  @override
  String get settingsNavAbout => 'Info';

  @override
  String get piiExportStepFormat => 'Format';

  @override
  String get piiExportStepScan => 'PII-Prüfung';

  @override
  String get piiExportStepConfirm => 'Bestätigen';

  @override
  String get piiExportNoPiiTitle => 'Keine PII-Daten erkannt';

  @override
  String get piiExportNoPiiSubtitle =>
      'Alle Spalten werden unverändert exportiert';

  @override
  String piiExportDetectedCount(int count) {
    return '$count Spalten mit PII erkannt';
  }

  @override
  String get piiExportHighSensitivity => '(hoch sensibel)';

  @override
  String get piiExportKeep => 'Behalten';

  @override
  String get piiExportMask => 'Maskieren';

  @override
  String get piiExportHash => 'Hashen';

  @override
  String get piiExportDrop => 'Spalte löschen';

  @override
  String get piiExportReadyTitle => 'Export bereit';

  @override
  String get piiExportSummaryFormat => 'Format';

  @override
  String get piiExportSummaryRows => 'Zeilen';

  @override
  String get piiExportSummaryPiiColumns => 'Verarbeitete PII-Spalten';

  @override
  String get piiExportFootnote =>
      'PII-Spalten werden gemäß Auswahl verarbeitet; Spalten ohne PII werden unverändert exportiert';

  @override
  String get serverBarNotConnected => 'Nicht verbunden';

  @override
  String get serverBarConnecting => 'Verbinde…';

  @override
  String get serverBarLocal => 'Lokal';

  @override
  String get serverBarConnected => 'Verbunden';

  @override
  String get serverBarReconnecting => 'Verbindung wird wiederhergestellt…';

  @override
  String serverBarReconnectingIn(int seconds) {
    return 'Wiederholung in $seconds s…';
  }

  @override
  String serverBarServerUrl(String url) {
    return 'Server: $url';
  }

  @override
  String get serverBarDisconnect => 'Trennen';

  @override
  String get serverBarUnknownUser => 'Unbekannt';

  @override
  String get serverConnectUnexpectedError =>
      'Ein unerwarteter Fehler ist aufgetreten.';

  @override
  String get cellViewerCopy => 'Kopieren';

  @override
  String cellViewerChars(Object count) {
    return '$count Zeichen';
  }

  @override
  String get slowQueryMenuLabel => 'Slow-Query-Statistik';

  @override
  String get slowQueryDialogTitle => 'Slow-Query-Statistik';

  @override
  String slowQueryScopeBanner(int thresholdMs) {
    return 'Erfasst Abfragen über dbmaster/server langsamer als $thresholdMs ms; wenn die native Slow-Log-Erfassung auf der Instanz aktiviert ist, werden auch die eigenen Slow Queries der Datenbank einbezogen (per Quelle unterschieden).';
  }

  @override
  String get slowQueryWindow1h => 'Letzte Stunde';

  @override
  String get slowQueryWindow24h => 'Letzte 24 Stunden';

  @override
  String get slowQueryWindow7d => 'Letzte 7 Tage';

  @override
  String get slowQuerySortTotalMs => 'Gesamtzeit';

  @override
  String get slowQuerySortCount => 'Anzahl';

  @override
  String get slowQuerySortAvgMs => 'Ø Zeit';

  @override
  String get slowQuerySortMaxMs => 'Max. Zeit';

  @override
  String get slowQueryAllConnections => 'Alle Verbindungen';

  @override
  String slowQueryDigestStats(int count, String total, String avg, String max) {
    return '$count Aufrufe · gesamt $total · ø $avg · max $max';
  }

  @override
  String slowQueryLastSeen(String time) {
    return 'zuletzt $time';
  }

  @override
  String get slowQueryEmptyTitle => 'Keine Slow Queries';

  @override
  String get slowQueryEmptyBody =>
      'In diesem Zeitraum lag nichts über der Sampling-Schwelle. Führe etwas Langsames über dbmaster aus und schau erneut vorbei.';

  @override
  String get slowQueryLoadFailed =>
      'Slow-Query-Statistik konnte nicht geladen werden.';

  @override
  String get slowQueryRetry => 'Erneut versuchen';

  @override
  String slowQueryLoadMore(int shown, int total) {
    return 'Mehr anzeigen ($shown von $total)';
  }

  @override
  String get slowQueryStatusOk => 'ok';

  @override
  String get slowQueryStatusError => 'Fehler';

  @override
  String get slowQueryStatusCancelled => 'abgebrochen';

  @override
  String get slowQueryDatabaseLabel => 'Datenbank';

  @override
  String get slowQueryNoPlaintext =>
      'Klartext-SQL ist auf dieser Instanz deaktiviert (nur Digest).';

  @override
  String get slowQueryCopySql => 'SQL kopieren';

  @override
  String get slowQueryCopied => 'Kopiert';

  @override
  String get reportsMenuLabel => 'Berichte';

  @override
  String get reportsDialogTitle => 'Berichte';

  @override
  String get reportsGenerateButton => 'Wochenbericht erstellen';

  @override
  String get reportsGeneratedToast => 'Wochenbericht erstellt.';

  @override
  String get reportsExistingToast =>
      'Der Wochenbericht dieser Woche existiert bereits.';

  @override
  String get reportsEmptyTitle => 'Keine Berichte';

  @override
  String get reportsEmptyBody =>
      'Erstelle den Slow-Query-Wochenbericht manuell oder warte auf den Wochenrhythmus.';

  @override
  String get reportsLoadFailed => 'Berichte konnten nicht geladen werden.';

  @override
  String get reportsRetry => 'Erneut versuchen';

  @override
  String reportsLoadMore(int shown, int total) {
    return 'Mehr anzeigen ($shown von $total)';
  }

  @override
  String get reportsWindowLabel => 'Zeitraum';

  @override
  String get reportsTruncatedHint =>
      'Unvollständiger Zeitraum: ältere Stichproben wurden bereits durch die Aufbewahrung entfernt.';

  @override
  String get reportsSamplesLabel => 'Stichproben';

  @override
  String get reportsDistinctLabel => 'Unterschiedliche Abfragen';

  @override
  String get reportsTotalTimeLabel => 'Gesamtzeit';

  @override
  String get reportsErrorsLabel => 'Fehler';

  @override
  String get reportsWowLabel => 'vs. Vorwoche';

  @override
  String get reportsTopSection => 'Top-Abfragen';

  @override
  String get reportsByDaySection => 'Pro Tag';

  @override
  String get reportsByConnectionSection => 'Pro Verbindung';

  @override
  String get reportsUnknownType => 'Unbekannter Berichtstyp — Rohinhalt:';

  @override
  String get reportsAnalyzeWithAi => 'Mit KI analysieren';
}
