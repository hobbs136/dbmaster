// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get filterBarApply => 'Appliquer';

  @override
  String get filterBarAddCondition => 'Ajouter une condition';

  @override
  String get filterBarAnd => 'ET';

  @override
  String get filterBarOr => 'OU';

  @override
  String get filterBarNoColumns => 'Aucune colonne';

  @override
  String get filterBarLoading => 'Chargement…';

  @override
  String get mongoAutocompleteTitle => 'Auto-complétion Mongo';

  @override
  String get appTitle => 'DbMaster';

  @override
  String get settingsTitle => 'Paramètres';

  @override
  String get settingsLanguage => 'Langue';

  @override
  String get settingsTheme => 'Thème';

  @override
  String get settingsGeneral => 'Général';

  @override
  String get settingsConnection => 'Connexion';

  @override
  String get settingsEditor => 'Éditeur';

  @override
  String get settingsAbout => 'À propos';

  @override
  String get connectionNewConnection => 'Nouvelle connexion';

  @override
  String get connectionEditConnection => 'Modifier la connexion';

  @override
  String get connectionManageConnection => 'Gérer les connexions';

  @override
  String get connectionDeleteConnection => 'Supprimer la connexion';

  @override
  String get connectionConnect => 'Connecter';

  @override
  String get connectionCreateDatabase => 'Créer une base de données';

  @override
  String get connectionEnableReadOnly => 'Activer lecture seule';

  @override
  String get connectionDisableReadOnly => 'Désactiver lecture seule';

  @override
  String connectionMoveToGroup(String groupName) {
    return 'Déplacer vers $groupName';
  }

  @override
  String get connectionRemoveFromGroup => 'Retirer du groupe';

  @override
  String get connectionCollapseAll => 'Tout réduire';

  @override
  String get connectionDisconnect => 'Déconnecter';

  @override
  String get connectionTestConnection => 'Tester la connexion';

  @override
  String get connectionConnectionName => 'Nom de la connexion';

  @override
  String get connectionHost => 'Hôte';

  @override
  String get connectionPort => 'Port';

  @override
  String get connectionUsername => 'Nom d\'utilisateur';

  @override
  String get connectionPassword => 'Mot de passe';

  @override
  String get connectionDatabase => 'Base de données';

  @override
  String get connectionEnvironment => 'Environnement';

  @override
  String get connectionEnvironmentNone => 'Aucun';

  @override
  String get commonSave => 'Enregistrer';

  @override
  String get commonCancel => 'Annuler';

  @override
  String get commonDelete => 'Supprimer';

  @override
  String get commonEdit => 'Modifier';

  @override
  String get commonAdd => 'Ajouter';

  @override
  String get commonClose => 'Fermer';

  @override
  String get commonDone => 'Done';

  @override
  String get commonSelect => 'Select';

  @override
  String get commonConfirm => 'Confirmer';

  @override
  String get commonSearch => 'Rechercher';

  @override
  String get commonRefresh => 'Actualiser';

  @override
  String get commonLoading => 'Chargement...';

  @override
  String get commonNoData => 'Aucune donnée';

  @override
  String get commonSuccess => 'Succès';

  @override
  String get commonError => 'Erreur';

  @override
  String get commonWarning => 'Avertissement';

  @override
  String get tableNewTable => 'Nouvelle table';

  @override
  String get tableEditTable => 'Modifier la table';

  @override
  String get tableDeleteTable => 'Supprimer la table';

  @override
  String get tableTableName => 'Nom de la table';

  @override
  String get tableColumns => 'Colonnes';

  @override
  String get tableIndexes => 'Index';

  @override
  String get tablePrimaryKey => 'Clé primaire';

  @override
  String get tableForeignKey => 'Clé étrangère';

  @override
  String get tableRenameTable => 'Renommer la table';

  @override
  String get tableNewTableName => 'Nouveau nom de table';

  @override
  String get queryExecute => 'Exécuter';

  @override
  String get queryExecuteSelected => 'Exécuter la sélection';

  @override
  String get queryFormat => 'Formater';

  @override
  String get queryClear => 'Effacer';

  @override
  String get queryHistory => 'Historique';

  @override
  String get queryResults => 'Résultats';

  @override
  String get sidebarConnections => 'Connexions';

  @override
  String get sidebarDatabases => 'Bases de données';

  @override
  String get sidebarTables => 'Tables';

  @override
  String get sidebarKeys => 'Clés';

  @override
  String get sidebarCollections => 'Collections';

  @override
  String get sidebarSuperTables => 'SuperTables';

  @override
  String get sidebarViews => 'Vues';

  @override
  String get sidebarSavedQueries => 'Requêtes enregistrées';

  @override
  String get sidebarProcedures => 'Procédures stockées';

  @override
  String get sidebarTriggers => 'Déclencheurs';

  @override
  String get sidebarFunctions => 'Fonctions';

  @override
  String get sidebarServer => 'Serveur';

  @override
  String get sidebarProcessList => 'Liste des processus';

  @override
  String get sidebarServerStatus => 'État du serveur';

  @override
  String get sidebarNoUsers => 'Aucun utilisateur';

  @override
  String get sidebarNoActiveProcesses => 'Aucun processus actif';

  @override
  String sidebarTdColsTags(int cols, int tags) {
    return '$cols col., $tags étiquettes';
  }

  @override
  String sidebarTdColumnsCount(int count) {
    return 'Colonnes ($count)';
  }

  @override
  String sidebarTdTagsCount(int count) {
    return 'Étiquettes ($count)';
  }

  @override
  String get sidebarTdDeleteTitle => 'Supprimer la SuperTable';

  @override
  String sidebarTdDeleteConfirm(String name) {
    return 'Voulez-vous vraiment supprimer la SuperTable « $name » ?\n\nToutes ses SubTables seront également supprimées !';
  }

  @override
  String get sidebarDeleteGroup => 'Supprimer le groupe';

  @override
  String get sidebarDeleteGroupPrompt => 'Sélectionner un groupe à supprimer :';

  @override
  String get sidebarConnectionSwitch => 'Changer de connexion';

  @override
  String get sidebarSelectConnectionHint =>
      'Sélectionnez une connexion dans le sélecteur ci-dessus pour commencer';

  @override
  String get sidebarConnectionNone => 'Aucune connexion';

  @override
  String get sidebarManageConnections => 'Gérer les connexions…';

  @override
  String get sidebarExtensions => 'Extensions';

  @override
  String get noExtensionsInstalled => 'No extensions installed';

  @override
  String get sidebarSchemas => 'Schémas';

  @override
  String get sidebarMaterializedViews => 'Vues matérialisées';

  @override
  String get sidebarSequences => 'Séquences';

  @override
  String get settingsGeneralSettings => 'Paramètres généraux';

  @override
  String get settingsAppearanceSettings => 'Apparence';

  @override
  String get settingsEditorSettings => 'Paramètres de l\'éditeur';

  @override
  String get settingsEnableAutocomplete => 'Activer l\'autocomplétion';

  @override
  String get settingsAutocompleteDescription =>
      'Suggérer automatiquement les mots-clés SQL et les noms de tables';

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
  String get settingsAiSettings => 'Paramètres IA';

  @override
  String get settingsAutoExecuteSql => 'Exécuter SQL automatiquement';

  @override
  String get settingsAutoExecuteSqlDescription =>
      'Exécuter automatiquement SQL lorsqu\'un onglet est ouvert';

  @override
  String get settingsThemeSettings => 'Thème';

  @override
  String get settingsDarkMode => 'Sombre';

  @override
  String get settingsLightMode => 'Clair';

  @override
  String get shortcutCategoryFile => 'Fichier';

  @override
  String get shortcutCategoryEdit => 'Édition';

  @override
  String get shortcutCategoryView => 'Affichage';

  @override
  String get shortcutCategoryAi => 'IA';

  @override
  String get shortcutCategoryTab => 'Onglets';

  @override
  String get shortcutNewConnection => 'Nouvelle connexion';

  @override
  String get shortcutNewTab => 'Nouvel onglet';

  @override
  String get shortcutCloseTab => 'Fermer l\'onglet';

  @override
  String get shortcutSaveQuery => 'Enregistrer la requête';

  @override
  String get shortcutExportData => 'Exporter les données';

  @override
  String get shortcutExecuteQuery => 'Exécuter la requête';

  @override
  String get shortcutExecuteQueryNewTab => 'Exécuter dans un nouvel onglet';

  @override
  String get shortcutFormatSql => 'Formater SQL';

  @override
  String get shortcutFind => 'Rechercher';

  @override
  String get shortcutReplace => 'Remplacer';

  @override
  String get shortcutAutocomplete => 'Autocomplétion';

  @override
  String get shortcutUndo => 'Annuler';

  @override
  String get shortcutRedo => 'Rétablir';

  @override
  String get shortcutToggleSidebar => 'Basculer la barre latérale';

  @override
  String get shortcutToggleAiPanel => 'Basculer le panneau IA';

  @override
  String get shortcutCommandPalette => 'Palette de commandes';

  @override
  String get shortcutShortcutHelp => 'Aide sur les raccourcis';

  @override
  String get shortcutGenerateSql => 'Générer SQL';

  @override
  String get shortcutOptimizeSql => 'Optimiser SQL';

  @override
  String get shortcutExplainSql => 'Expliquer SQL';

  @override
  String get shortcutNextTab => 'Onglet suivant';

  @override
  String get shortcutPreviousTab => 'Onglet précédent';

  @override
  String get shortcutSwitchToTab => 'Basculer vers l\'onglet';

  @override
  String get shortcutToggleAiFullscreen => 'Panneau IA en plein écran';

  @override
  String get shortcutAuditLog => 'Journal d\'audit des requêtes';

  @override
  String get shortcutIncreaseOpacity => 'Augmenter l\'opacité du panneau';

  @override
  String get shortcutDecreaseOpacity => 'Diminuer l\'opacité du panneau';

  @override
  String get tableCreateNewTable => 'Créer un nouveau tableau';

  @override
  String get toolbarBackup => 'Sauvegarde';

  @override
  String get toolbarImport => 'Importer';

  @override
  String get toolbarExport => 'Exporter';

  @override
  String get sidebarExpand => 'Développer la barre latérale';

  @override
  String get sidebarSettings => 'Paramètres';

  @override
  String get sidebarSearchHint => 'Rechercher des connexions, tables, vues...';

  @override
  String sidebarConnectionActive(Object count) {
    return '$count connexions actives';
  }

  @override
  String get sidebarNoConnections => 'Aucune connexion enregistrée';

  @override
  String get sidebarClickToCreateConnection =>
      'Cliquez sur le bouton ci-dessous pour créer une nouvelle connexion';

  @override
  String get sidebarCreateConnection => 'Nouvelle connexion';

  @override
  String get resultsExport => 'Exporter';

  @override
  String get resultsSave => 'Enregistrer';

  @override
  String get resultsDiscard => 'Abandonner';

  @override
  String get resultsNoDataToExport => 'Aucune donnée à exporter';

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
  String get resultsConfirmDiscardChanges =>
      'Confirmer l\'abandon des modifications';

  @override
  String resultsDiscardChangesMessage(Object count) {
    return 'Êtes-vous sûr de vouloir abandonner $count modifications ? Cette action est irréversible.';
  }

  @override
  String get resultsContinueEditing => 'Continuer l\'édition';

  @override
  String get resultsDiscardChanges => 'Abandonner les modifications';

  @override
  String get resultsConfirmExecuteSQL => 'Confirmer l\'exécution SQL';

  @override
  String get resultsBarChart => 'Graphique à barres';

  @override
  String get resultsLineChart => 'Graphique linéaire';

  @override
  String get resultsPieChart => 'Graphique circulaire';

  @override
  String get resultsSelectAxisFields =>
      'Veuillez sélectionner les champs des axes X et Y';

  @override
  String get statusNotConnected => 'Non connecté';

  @override
  String get statusConnected => 'Connecté';

  @override
  String statusTables(Object count) {
    return '$count tables';
  }

  @override
  String get statusNone => 'Aucun';

  @override
  String statusVersion(Object version) {
    return 'v$version';
  }

  @override
  String get backupManagement => 'Gestion des sauvegardes';

  @override
  String get backupList => 'Liste des sauvegardes';

  @override
  String get createBackup => 'Créer une sauvegarde';

  @override
  String get noBackupFiles => 'Aucun fichier de sauvegarde';

  @override
  String get clickCreateBackupTab =>
      'Cliquez sur l\'onglet \'Créer une sauvegarde\' pour commencer';

  @override
  String get importBackup => 'Importer une sauvegarde';

  @override
  String get previewContent => 'Aperçu du contenu';

  @override
  String get exportFile => 'Exporter le fichier';

  @override
  String get restoreBackup => 'Restaurer la sauvegarde';

  @override
  String get selectBackupToView =>
      'Sélectionnez une sauvegarde pour voir les détails';

  @override
  String get database => 'Base de données';

  @override
  String get backupType => 'Type';

  @override
  String get backupSize => 'Taille';

  @override
  String get createdAt => 'Date de création';

  @override
  String get tableCount => 'Nombre de tables';

  @override
  String get description => 'Description';

  @override
  String get preview => 'Aperçu';

  @override
  String get export => 'Exporter';

  @override
  String get restore => 'Restaurer';

  @override
  String get confirmRestore => 'Confirmer la restauration';

  @override
  String confirmRestoreMessage(Object name) {
    return 'Êtes-vous sûr de vouloir restaurer la sauvegarde \"$name\" ?\n\nCela exécutera toutes les instructions SQL du fichier de sauvegarde et pourrait écraser les données existantes.';
  }

  @override
  String get confirmDelete => 'Confirmer la suppression';

  @override
  String confirmDeleteMessage(Object name) {
    return 'Êtes-vous sûr de vouloir supprimer la sauvegarde \"$name\" ?\n\nCette action est irréversible.';
  }

  @override
  String get backupFormat => 'Format de sauvegarde';

  @override
  String get backupContent => 'Contenu de la sauvegarde';

  @override
  String get selectTablesHint =>
      'Sélectionner les tables (laisser vide pour tout sauvegarder)';

  @override
  String get advancedOptions => 'Options avancées';

  @override
  String get includeStructure => 'Inclure la structure';

  @override
  String get includeStructureDesc => 'Instructions CREATE TABLE';

  @override
  String get includeData => 'Inclure les données';

  @override
  String get includeDataDesc => 'Instructions INSERT ou lignes de données';

  @override
  String get noTablesAvailable => 'Aucune table disponible';

  @override
  String get selectAll => 'Tout sélectionner';

  @override
  String get deselectAll => 'Tout désélectionner';

  @override
  String tablesSelected(Object count) {
    return '$count tables sélectionnées';
  }

  @override
  String get addDropTable => 'Ajouter DROP TABLE';

  @override
  String get useExtendedInsert => 'Utiliser INSERT étendu';

  @override
  String get useExtendedInsertDesc =>
      'Fusionner plusieurs lignes en une seule instruction INSERT';

  @override
  String get rowLimitPerTable => 'Limite de lignes par table (optionnel)';

  @override
  String get leaveEmptyForNoLimit => 'Laisser vide pour aucune limite';

  @override
  String get whereCondition => 'Condition WHERE (optionnel)';

  @override
  String get whereConditionExample => 'Exemple : id > 100';

  @override
  String get enterBackupDescription =>
      'Entrer une description de sauvegarde (optionnel)';

  @override
  String get startBackup => 'Démarrer la sauvegarde';

  @override
  String get backupProgress => 'Progression de la sauvegarde';

  @override
  String get waitingToStartBackup =>
      'En attente du démarrage de la sauvegarde...';

  @override
  String get currentTable => 'Table actuelle';

  @override
  String get progressPercent => 'Progression';

  @override
  String get backupComplete => 'Sauvegarde terminée !';

  @override
  String get backupFailed => 'Échec de la sauvegarde';

  @override
  String get loadBackupListFailed =>
      'Échec du chargement de la liste des sauvegardes';

  @override
  String get retry => 'Réessayer';

  @override
  String get previewFailed => 'Échec de l\'aperçu';

  @override
  String get exportedTo => 'Exporté vers';

  @override
  String get backupRestoreSuccess => 'Sauvegarde restaurée avec succès';

  @override
  String get restoreFailed => 'Échec de la restauration';

  @override
  String get backupDeleted => 'Sauvegarde supprimée';

  @override
  String deleteFailed(Object error) {
    return 'Échec de la suppression : $error';
  }

  @override
  String get selectBackupFile => 'Sélectionner un fichier de sauvegarde';

  @override
  String get backupImportSuccess => 'Fichier de sauvegarde importé avec succès';

  @override
  String importFailed(String error) {
    return 'Échec de l\'importation : $error';
  }

  @override
  String get selectAtLeastOneOption =>
      'Veuillez sélectionner au moins la structure ou les données de sauvegarde';

  @override
  String get backupFailedError => 'Échec de la sauvegarde';

  @override
  String get aiAssistant => 'Assistant IA';

  @override
  String get aiAnalyze => 'Analyse IA';

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
  String get apiSettings => 'Paramètres API';

  @override
  String get clearChat => 'Effacer la conversation';

  @override
  String get model => 'Modèle';

  @override
  String get enterModelName => 'Entrer le nom du modèle';

  @override
  String get autoExecuteSql => 'Exécuter SQL automatiquement';

  @override
  String get autoExecuteSqlDesc =>
      'Lorsqu\'activé, les requêtes générées par l\'IA seront exécutées automatiquement';

  @override
  String get aiDatabaseAssistant => 'Assistant de base de données IA';

  @override
  String get aiAssistantDesc =>
      'Supporte plusieurs fournisseurs de modèles d\'IA\nVous aide à écrire SQL, optimiser les requêtes, expliquer la structure de la base de données';

  @override
  String get enterYourQuestion => 'Entrez votre question...';

  @override
  String configureApiKeyFirst(Object provider) {
    return 'Veuillez d\'abord configurer la clé API $provider dans les paramètres pour activer la fonction de chat IA.\n\nCliquez sur l\'icône des paramètres en haut à droite pour configurer.';
  }

  @override
  String get generationFailed => 'Échec de la génération';

  @override
  String get stepAnalyzeNeeds =>
      'Étape 1 : Analyse des besoins de l\'utilisateur, détermination des tables à interroger...';

  @override
  String get stepGetTableSchema =>
      'Étape 2 : Récupération des instructions CREATE TABLE détaillées...';

  @override
  String get stepGenerateSql => 'Étape 3 : Génération de l\'instruction SQL...';

  @override
  String get analysisResultTables =>
      'Résultat de l\'analyse : Tables à interroger';

  @override
  String get tableSchemaInfo => 'Informations sur la structure de la table';

  @override
  String get operationCancelled => 'Opération annulée';

  @override
  String get executingSql => 'Exécution du SQL en cours...';

  @override
  String executeSuccessRows(Object count) {
    return 'Exécution réussie, $count lignes de données retournées';
  }

  @override
  String get executeFailedError => 'Échec de l\'exécution';

  @override
  String get confirmDangerousOperation =>
      'Confirmer l\'exécution d\'une opération dangereuse ?';

  @override
  String get confirmExecuteSql => 'Confirmer l\'exécution SQL';

  @override
  String get dangerousOperationWarning =>
      'Cette opération pourrait modifier ou supprimer des données, veuillez procéder avec prudence !';

  @override
  String get sqlCopied => 'SQL copié';

  @override
  String get sqlGenerationComplete => 'Génération SQL terminée';

  @override
  String get dangerousOperation => 'Opération dangereuse';

  @override
  String get dangerousOperationDesc =>
      'Ceci est une opération dangereuse, veuillez la traiter avec prudence';

  @override
  String get taskCompleteDesc =>
      'Tâche terminée, vous pouvez choisir d\'exécuter ou de copier le SQL';

  @override
  String get generatedSql => 'SQL généré';

  @override
  String get dangerous => 'Dangereux';

  @override
  String get confirmExecute => 'Confirmer l\'exécution';

  @override
  String get requestTimeout => 'Délai d\'expiration de la requête';

  @override
  String get seconds => 'secondes';

  @override
  String get apiSettingsSaved => 'Paramètres API enregistrés';

  @override
  String get dataImport => 'Importation de données';

  @override
  String get selectFile => 'Sélectionner un fichier';

  @override
  String get noFileSelected => 'Aucun fichier sélectionné';

  @override
  String get importConfig => 'Configuration de l\'importation';

  @override
  String get targetTableName => 'Nom de la table cible';

  @override
  String get enterTableName => 'Entrer le nom de la table';

  @override
  String get includeHeader => 'Inclure l\'en-tête';

  @override
  String get delimiter => 'Délimiteur';

  @override
  String get overwriteTable => 'Écraser la table';

  @override
  String get deleteExistingTable => '(Supprimer la table existante)';

  @override
  String get batchSize => 'Taille du lot';

  @override
  String dataPreviewRows(Object count) {
    return 'Aperçu des données ($count lignes)';
  }

  @override
  String get pleaseSelectFile =>
      'Veuillez sélectionner un fichier pour prévisualiser les données';

  @override
  String get importProgress => 'Progression de l\'importation';

  @override
  String get importPreparing => 'Préparation de l\'importation...';

  @override
  String get totalRecords => 'Total';

  @override
  String get importedRecords => 'Importé';

  @override
  String get failedRecords => 'Échoué';

  @override
  String get readyToImport => 'Prêt à importer';

  @override
  String get importingData => 'Importation des données en cours...';

  @override
  String get importComplete => 'Importation terminée !';

  @override
  String get parseFileFailed => 'Échec de l\'analyse du fichier';

  @override
  String get noDataToImport => 'Aucune donnée à importer';

  @override
  String get selectDatabaseFirst =>
      'Veuillez d\'abord sélectionner une base de données';

  @override
  String get importFailedError => 'Échec de l\'importation';

  @override
  String get startImport => 'Démarrer l\'importation';

  @override
  String get importing => 'Importation en cours...';

  @override
  String get optimizeSql => 'Optimiser SQL';

  @override
  String get explainQuery => 'Expliquer la requête';

  @override
  String get generateInsert => 'Générer INSERT';

  @override
  String get generateUpdate => 'Générer UPDATE';

  @override
  String get generateDelete => 'Générer DELETE';

  @override
  String get createTableStatement => 'Instruction CREATE TABLE';

  @override
  String get securityCheck => 'Vérification de sécurité';

  @override
  String get indexSuggestion => 'Suggestion d\'index';

  @override
  String get executionPlan => 'Plan d\'exécution';

  @override
  String get pleaseEnterSql => 'Veuillez d\'abord entrer une instruction SQL';

  @override
  String get pleaseConnectDatabase =>
      'Veuillez d\'abord connecter une base de données';

  @override
  String get analysisFailed => 'Échec de l\'analyse';

  @override
  String get loadHistoryFailed => 'Échec du chargement de l\'historique';

  @override
  String get noQueryHistory =>
      'Aucun historique de requêtes\n\nAprès avoir exécuté des requêtes SQL, l\'historique sera sauvegardé ici.';

  @override
  String queryHistoryRecords(Object count) {
    return 'Historique des requêtes ($count les plus récentes)';
  }

  @override
  String get databaseType => 'Type de base de données';

  @override
  String get server => 'Serveur';

  @override
  String get currentDatabase => 'Base de données actuelle';

  @override
  String get notConnected => 'Non connecté';

  @override
  String get notSelected => 'Non sélectionné';

  @override
  String get tableName => 'Nom de la table';

  @override
  String get tableStructureInfo => 'Informations sur la structure de la table';

  @override
  String get createStatement => 'Instruction CREATE';

  @override
  String andMoreTables(Object count) {
    return '... et $count tables supplémentaires';
  }

  @override
  String get primaryKey => 'Clé primaire';

  @override
  String get executionTime => 'Temps d\'exécution';

  @override
  String get status => 'Statut';

  @override
  String get commonFailed => 'Échec';

  @override
  String get format => 'Format';

  @override
  String get connectionDefaultDatabase => 'Base de données par défaut';

  @override
  String get connectionSavePassword => 'Sauvegarder le mot de passe';

  @override
  String get connectionAdvancedOptions => 'Options avancées';

  @override
  String get connectionTimeout => 'Délai d\'expiration (secondes)';

  @override
  String get connectionUseSSL => 'Utiliser SSL/TLS';

  @override
  String get connectionEnableSecureConnection =>
      'Activer la connexion sécurisée';

  @override
  String get connectionUseTls => 'Utiliser TLS/SSL';

  @override
  String get connectionUseTlsDesc =>
      'Connexion chiffrée via TLS (établie côté serveur)';

  @override
  String get connectionTlsInsecure =>
      'Ignorer la vérification du certificat (non sécurisé)';

  @override
  String get connectionTlsInsecureDesc =>
      'Ne pas vérifier le certificat du serveur — environnements de confiance/test uniquement';

  @override
  String get connectionSshSubtitleGateway =>
      'Le tunnel SSH est établi côté serveur dbmaster (configuration transmise avec la connexion)';

  @override
  String get connectionAutoReconnect => 'Reconnexion automatique';

  @override
  String get connectionAutoReconnectDesc =>
      'Tenter de se reconnecter automatiquement lorsque la connexion est perdue';

  @override
  String get connectionCharset => 'Jeu de caractères';

  @override
  String get connectionTimezone => 'Fuseau horaire';

  @override
  String get connectionTestSuccess => 'Connexion réussie !';

  @override
  String connectionTestFailed(String error) {
    return 'Échec de la connexion';
  }

  @override
  String get connectionDatabaseType => 'Type de base de données';

  @override
  String get connectionManager => 'Gestionnaire de connexions';

  @override
  String get connectionSavedConnections => 'Connexions enregistrées';

  @override
  String get connectionNoSavedConnections => 'Aucune connexion enregistrée';

  @override
  String get connectionCurrent => 'Actuel';

  @override
  String get connectionConnected => 'Connecté';

  @override
  String get connectionSwitchToConnection => 'Basculer vers cette connexion';

  @override
  String get connectionCloneConnection => 'Cloner la connexion';

  @override
  String get connectionCloned => 'Connexion clonée';

  @override
  String get connectionDeleteConnectionTitle => 'Supprimer la connexion';

  @override
  String get connectionDeleteConnectionConfirm =>
      'Êtes-vous sûr de vouloir supprimer la connexion';

  @override
  String get connectionDisconnectAll => 'Déconnecter tout';

  @override
  String get searchDialogTitle => 'Recherche';

  @override
  String get searchHint =>
      'Rechercher des tables, vues, procédures stockées, colonnes...';

  @override
  String get searchNoResults => 'Aucun objet trouvé';

  @override
  String get searchTryDifferentKeywords => 'Essayez des mots-clés différents';

  @override
  String get searchNavigate => 'Naviguer';

  @override
  String get searchSelect => 'Sélectionner';

  @override
  String get searchClose => 'Fermer';

  @override
  String searchResultsCount(Object count) {
    return '$count résultats';
  }

  @override
  String get searchTypeConnection => 'Connexion';

  @override
  String get searchTypeDatabase => 'Base de données';

  @override
  String get searchTypeTable => 'Table';

  @override
  String get searchTypeView => 'Vue';

  @override
  String get searchTypeProcedure => 'Procédure stockée';

  @override
  String get searchTypeColumn => 'Colonne';

  @override
  String get savedQueriesTitle => 'Requêtes enregistrées';

  @override
  String get savedQueriesNoQueries => 'Aucune requête enregistrée';

  @override
  String get savedQueriesDeleteTitle => 'Supprimer la requête';

  @override
  String get savedQueriesDeleteConfirm =>
      'Êtes-vous sûr de vouloir supprimer cette requête ?';

  @override
  String get savedQueriesOpen => 'Ouvrir';

  @override
  String get viewJson => 'Voir le JSON';

  @override
  String get extractFieldAsColumn => 'Extraire champ comme colonne';

  @override
  String get erDiagramTitle => 'Diagramme ER';

  @override
  String get erDiagramSearchTables => 'Rechercher des tables...';

  @override
  String get erDiagramHierarchicalLayout => 'Disposition hiérarchique';

  @override
  String get erDiagramForceDirectedLayout => 'Disposition par force';

  @override
  String get erDiagramCircleLayout => 'Disposition circulaire';

  @override
  String get erDiagramResetLayout => 'Réinitialiser la disposition';

  @override
  String get erDiagramZoomIn => 'Zoom avant';

  @override
  String get erDiagramZoomOut => 'Zoom arrière';

  @override
  String get erDiagramFitToScreen => 'Ajuster à l\'écran';

  @override
  String get erDiagramRelations => 'Relations';

  @override
  String get erDiagramZoom => 'Zoom';

  @override
  String get erDiagramShowIsolated => 'Afficher isolés';

  @override
  String get erDiagramExportAsPNG => 'Exporter en PNG';

  @override
  String get erDiagramExportAsJPG => 'Exporter en JPG';

  @override
  String get erDiagramLoading => 'Chargement du diagramme ER...';

  @override
  String get erDiagramErrorLoading =>
      'Erreur lors du chargement du diagramme ER';

  @override
  String get erDiagramNoData => 'Aucune donnée de diagramme disponible';

  @override
  String get erDiagramRetry => 'Réessayer';

  @override
  String get erDiagramSelectConnection => 'Sélectionner une connexion';

  @override
  String get erDiagramSelectDatabase => 'Sélectionner une base de données';

  @override
  String get performanceAnalyzerTitle => 'Outil d\'analyse des performances';

  @override
  String get performanceAnalyzerSearch => 'Rechercher...';

  @override
  String get performanceAnalyzerRefresh => 'Actualiser les données';

  @override
  String get performanceAnalyzerGenerateReport => 'Générer le rapport';

  @override
  String get performanceAnalyzerExport => 'Exporter';

  @override
  String get performanceAnalyzerClose => 'Fermer';

  @override
  String get performanceAnalyzerNotConnected =>
      'Non connecté à une base de données';

  @override
  String get performanceAnalyzerNotConnectedDesc =>
      'Veuillez d\'abord vous connecter à une base de données pour utiliser les fonctionnalités d\'analyse des performances';

  @override
  String get performanceAnalyzerConfirm => 'Confirmer';

  @override
  String get performanceAnalyzerSlowQueryAnalysis =>
      'Analyse des requêtes lentes';

  @override
  String get performanceAnalyzerIndexAnalysis => 'Analyse des index';

  @override
  String get performanceAnalyzerTableStatistics => 'Statistiques des tables';

  @override
  String get performanceAnalyzerPerformanceReport => 'Rapport de performance';

  @override
  String get performanceAnalyzerLoading =>
      'Analyse des performances de la base de données en cours...';

  @override
  String get performanceAnalyzerLoadFailed => 'Échec du chargement';

  @override
  String get performanceAnalyzerRetry => 'Réessayer';

  @override
  String get performanceAnalyzerTimeThreshold => 'Seuil de temps :';

  @override
  String get performanceAnalyzerNoSlowQueries => 'Aucune requête lente trouvée';

  @override
  String get performanceAnalyzerSelectQuery =>
      'Sélectionnez une requête pour voir les détails';

  @override
  String get performanceAnalyzerQueryInfo => 'Informations sur la requête';

  @override
  String get performanceAnalyzerExecutionTime => 'Temps d\'exécution';

  @override
  String get performanceAnalyzerDatabase => 'Base de données';

  @override
  String get performanceAnalyzerRowsScaned => 'Lignes analysées';

  @override
  String get performanceAnalyzerRowsReturned => 'Lignes retournées';

  @override
  String get performanceAnalyzerTimestamp => 'Horodatage';

  @override
  String get performanceAnalyzerSqlStatement => 'Instruction SQL';

  @override
  String get performanceAnalyzerExecutionPlan => 'Plan d\'exécution';

  @override
  String get performanceAnalyzerOptimizationSuggestions =>
      'Suggestions d\'optimisation';

  @override
  String get performanceAnalyzerFullTableScan =>
      'Analyse complète de table détectée';

  @override
  String get performanceAnalyzerFullTableScanDesc =>
      'La requête utilise une analyse complète de table (type=ALL), un index est recommandé sur les colonnes WHERE';

  @override
  String get performanceAnalyzerFileSort => 'Tri de fichiers';

  @override
  String get performanceAnalyzerFileSortDesc =>
      'La requête utilise un tri de fichiers (Using filesort), un index est recommandé sur la colonne ORDER BY';

  @override
  String get performanceAnalyzerTempTable => 'Utilisation de table temporaire';

  @override
  String get performanceAnalyzerTempTableDesc =>
      'La requête utilise une table temporaire (Using temporary), envisagez d\'optimiser les requêtes GROUP BY ou DISTINCT';

  @override
  String get performanceAnalyzerLowScanEfficiency =>
      'Faible efficacité d\'analyse';

  @override
  String get performanceAnalyzerNoIssues => 'Aucun problème évident trouvé';

  @override
  String get performanceAnalyzerNoIssuesDesc =>
      'Le plan d\'exécution de la requête semble normal';

  @override
  String get performanceAnalyzerIndexTypeDistribution =>
      'Distribution des types d\'index';

  @override
  String get performanceAnalyzerNoData => 'Aucune donnée';

  @override
  String get performanceAnalyzerTotalIndexes => 'Total des index';

  @override
  String get performanceAnalyzerUsedIndexes => 'Utilisés';

  @override
  String get performanceAnalyzerUnusedIndexes => 'Non utilisés';

  @override
  String get performanceAnalyzerIndexes => 'index';

  @override
  String get performanceAnalyzerColumns => 'Colonnes :';

  @override
  String get performanceAnalyzerCardinality => 'Cardinalité :';

  @override
  String get performanceAnalyzerTotalTables => 'Total des tables';

  @override
  String get performanceAnalyzerTotalRows => 'Total des lignes';

  @override
  String get performanceAnalyzerDataSize => 'Taille des données';

  @override
  String get performanceAnalyzerIndexSize => 'Taille des index';

  @override
  String get performanceAnalyzerTotalSize => 'Taille totale';

  @override
  String get performanceAnalyzerTableName => 'Nom de la table';

  @override
  String get performanceAnalyzerEngine => 'Moteur';

  @override
  String get performanceAnalyzerRowCount => 'Nombre de lignes';

  @override
  String get performanceAnalyzerPercentage => 'Pourcentage';

  @override
  String get performanceAnalyzerTableSizeDistribution =>
      'Distribution de la taille des tables (Top 10)';

  @override
  String get performanceAnalyzerDatabasePerformanceReport =>
      'Rapport de performance de la base de données';

  @override
  String get performanceAnalyzerGeneratedAt => 'Généré le :';

  @override
  String get performanceAnalyzerTableCount => 'Nombre de tables';

  @override
  String get performanceAnalyzerSlowQueries => 'Requêtes lentes';

  @override
  String get performanceAnalyzerSuggestions => 'Suggestions';

  @override
  String get performanceAnalyzerImpact => 'Impact :';

  @override
  String get performanceAnalyzerImpactHigh => 'Élevé';

  @override
  String get performanceAnalyzerImpactMedium => 'Moyen';

  @override
  String get performanceAnalyzerImpactLow => 'Faible';

  @override
  String get performanceAnalyzerRecommendation => 'Action recommandée :';

  @override
  String get performanceAnalyzerSlowQueriesTop => 'Top des requêtes lentes';

  @override
  String get performanceAnalyzerLargeTableStatistics =>
      'Statistiques des grandes tables';

  @override
  String get performanceAnalyzerClickGenerateReport =>
      'Cliquez sur le bouton \"Générer le rapport\" pour commencer l\'analyse';

  @override
  String get sqlHistoryTitle => 'Historique SQL';

  @override
  String get sqlHistoryNoHistory => 'Aucun historique';

  @override
  String get sqlHistoryClose => 'Fermer';

  @override
  String get sqlHistoryDelete => 'Supprimer';

  @override
  String get sqlHistoryConfirmDelete => 'Confirmer la suppression';

  @override
  String get sqlHistoryDeleteConfirm =>
      'Êtes-vous sûr de vouloir supprimer cet enregistrement d\'historique ?';

  @override
  String get sqlHistoryJustNow => 'À l\'instant';

  @override
  String sqlHistoryMinutesAgo(Object count) {
    return 'Il y a $count minutes';
  }

  @override
  String sqlHistoryHoursAgo(Object count) {
    return 'Il y a $count heures';
  }

  @override
  String sqlHistoryDaysAgo(Object count) {
    return 'Il y a $count jours';
  }

  @override
  String get aiPanelApiSettings => 'Paramètres API';

  @override
  String get aiPanelApiKey => 'Clé API';

  @override
  String get aiPanelEnterApiKey => 'Entrer la clé API';

  @override
  String get aiPanelApiBaseUrl => 'URL de base de l\'API (optionnel)';

  @override
  String get aiPanelCustomApiUrl => 'URL API personnalisée';

  @override
  String get aiPanelRequestTimeout => 'Délai d\'expiration de la requête :';

  @override
  String get aiPanelSeconds => 'secondes';

  @override
  String get aiPanelSave => 'Enregistrer';

  @override
  String get aiPanelApiSettingsSaved => 'Paramètres API enregistrés';

  @override
  String get aiPanelConfirmDangerousOperation =>
      'Confirmer l\'exécution d\'une opération dangereuse ?';

  @override
  String get aiPanelConfirmExecuteSql => 'Confirmer l\'exécution SQL';

  @override
  String get aiPanelDangerousOperationWarning =>
      'Cette opération pourrait modifier ou supprimer des données, veuillez procéder avec prudence !';

  @override
  String get aiPanelCancel => 'Annuler';

  @override
  String get aiPanelConfirmExecute => 'Confirmer l\'exécution';

  @override
  String get aiPanelOperationCancelled => 'Opération annulée';

  @override
  String get aiPanelExecutingSql => 'Exécution du SQL en cours...';

  @override
  String aiPanelExecuteSuccess(Object count) {
    return 'Exécution réussie, $count lignes retournées';
  }

  @override
  String get aiPanelExecuteFailed => 'Échec de l\'exécution';

  @override
  String get aiPanelDataPreview => 'Aperçu des données';

  @override
  String aiPanelAndMoreRows(Object count) {
    return 'et $count lignes supplémentaires';
  }

  @override
  String aiPanelSqlExecutionSuccess(Object count) {
    return 'Exécution SQL réussie, $count lignes retournées';
  }

  @override
  String get aiPanelSqlGenerationComplete => 'Génération SQL terminée';

  @override
  String get aiPanelSqlGenerationCompleteWarning =>
      'Génération SQL terminée ⚠️';

  @override
  String get aiPanelTaskCompleteDesc =>
      'Tâche terminée, vous pouvez choisir d\'exécuter ou de copier le SQL';

  @override
  String get aiPanelDangerousOperationDesc =>
      'Ceci est une opération dangereuse, veuillez la traiter avec prudence';

  @override
  String get aiPanelGeneratedSql => 'SQL généré';

  @override
  String get aiPanelDangerous => 'Dangereux';

  @override
  String get aiPanelContinue => 'Continuer';

  @override
  String get aiPanelClose => 'Fermer';

  @override
  String get aiPanelCopy => 'Copier';

  @override
  String get aiPanelExecute => 'Exécuter';

  @override
  String get aiPanelConfirmExecuteDangerous => 'Confirmer l\'exécution';

  @override
  String get quickActionsTitle => 'Actions rapides';

  @override
  String get quickActionsNewTable => 'Nouvelle table';

  @override
  String get quickActionsNewQuery => 'Nouvelle requête';

  @override
  String get quickActionsAiAssistant => 'Assistant IA';

  @override
  String get quickActionsSelectDatabaseFirst =>
      'Veuillez d\'abord sélectionner une base de données';

  @override
  String get resultsTabResults => 'Résultats';

  @override
  String get resultsTabMessages => 'Messages';

  @override
  String get resultsTabExecutionPlan => 'Plan d\'exécution';

  @override
  String get resultsTabExecutionDetails => 'Execution Details';

  @override
  String get resultsSearchBtn => 'Rechercher';

  @override
  String get resultsSearchHint => 'Search in results…';

  @override
  String resultsSearchNoMatch(Object query) {
    return 'No rows match \"$query\"';
  }

  @override
  String get resultsClear => 'Effacer';

  @override
  String get resultsSubmit => 'Soumettre';

  @override
  String get resultsSearchResults => 'Rechercher dans les résultats';

  @override
  String get resultsViewTable => 'Tableau';

  @override
  String get resultsViewCard => 'Carte';

  @override
  String get resultsViewChart => 'Graphique';

  @override
  String get resultsViewStatistics => 'Statistiques';

  @override
  String get paginationShowing => 'Affichage';

  @override
  String get paginationRows => 'lignes';

  @override
  String get paginationFirstPage => 'Première page';

  @override
  String get paginationPreviousPage => 'Page précédente';

  @override
  String get paginationNextPage => 'Page suivante';

  @override
  String get paginationLastPage => 'Dernière page';

  @override
  String get editModeTitle => 'Mode édition';

  @override
  String get editModeChanges => 'modifications';

  @override
  String get editModeHint =>
      'Double-cliquer pour modifier | Entrée pour confirmer | Échap pour annuler | Tab pour basculer';

  @override
  String get resultsNoDataTitle => 'Aucun résultat';

  @override
  String get resultsNoDataMessage =>
      'Les résultats apparaîtront après l\'exécution d\'une requête';

  @override
  String get resultsNoDataCardMessage =>
      'La vue carte apparaîtra après l\'exécution d\'une requête';

  @override
  String get resultsNoDataChartMessage =>
      'Le graphique apparaîtra après l\'exécution d\'une requête';

  @override
  String get resultsNoDataStatisticsMessage =>
      'Les statistiques apparaîtront après l\'exécution d\'une requête';

  @override
  String get resultsNoDataExecutionPlanMessage =>
      'Cliquez sur le bouton \'Plan d\'exécution\' pour voir le plan d\'exécution de la requête';

  @override
  String get statisticsTotalRows => 'Nombre total de lignes';

  @override
  String get statisticsFieldInfo => 'Informations sur les champs';

  @override
  String get statisticsNumeric => 'Numérique';

  @override
  String get statisticsText => 'Texte';

  @override
  String get statisticsNumericStats => 'Statistiques numériques';

  @override
  String get statisticsCount => 'Nombre';

  @override
  String get statisticsSum => 'Somme';

  @override
  String get statisticsAvg => 'Moyenne';

  @override
  String get statisticsMin => 'Minimum';

  @override
  String get statisticsMax => 'Maximum';

  @override
  String get chartXAxis => 'Axe X';

  @override
  String get chartYAxis => 'Axe Y';

  @override
  String get chartType => 'Type : ';

  @override
  String get chartCannotGenerate =>
      'Impossible de générer le graphique : Veuillez vous assurer que le champ de l\'axe Y contient des données numériques';

  @override
  String messagesQuerySuccess(Object cols, Object rows) {
    return 'Requête réussie, $rows lignes, $cols colonnes retournées';
  }

  @override
  String get messagesExecuteToSeeResults =>
      'Les informations sur les résultats apparaîtront après l\'exécution d\'une requête';

  @override
  String sqlPreviewWillExecute(Object count, Object table) {
    return '$count instructions SQL seront exécutées sur la table `$table` :';
  }

  @override
  String get saveErrorNoTab =>
      'Impossible d\'enregistrer : L\'onglet actuel n\'existe pas';

  @override
  String get saveErrorCannotExtractTable =>
      'Impossible d\'enregistrer : Impossible d\'extraire le nom de la table de la requête';

  @override
  String saveErrorFailed(Object error) {
    return 'Échec de l\'enregistrement : $error';
  }

  @override
  String get exportSelectFormat => 'Sélectionner le format d\'exportation';

  @override
  String get toolbarExecute => 'Exécuter';

  @override
  String get toolbarStop => 'Arrêter';

  @override
  String get toolbarReadOnlyChip => 'Lecture seule';

  @override
  String get toolbarLimitChipTooltip =>
      'Limite de lignes pour cette connexion (LIMIT auto)';

  @override
  String get toolbarTimeoutChipTooltip =>
      'Délai de requête pour cette connexion';

  @override
  String get toolbarChipFollowSettings => 'Selon les paramètres';

  @override
  String get toolbarChipOff => 'Désactivé';

  @override
  String get toolbarChipFollowConnection => 'Selon la connexion';

  @override
  String get gridEditBlockedReadOnly =>
      'Connexion en lecture seule — édition des cellules désactivée.';

  @override
  String get gridEditBlockedNoTable =>
      'Impossible de déduire la table cible — l\'édition nécessite une requête mono-table.';

  @override
  String gridEditsCount(Object count, Object rows) {
    return '$count modification(s) sur $rows ligne(s)';
  }

  @override
  String get gridCommitButton => 'Valider les modifications';

  @override
  String get gridDiscardButton => 'Abandonner';

  @override
  String gridCommitSuccess(Object rows) {
    return '$rows ligne(s) écrite(s)';
  }

  @override
  String gridCommitNoPrimaryKey(Object table) {
    return 'La table $table n\'a pas de clé primaire — écriture impossible.';
  }

  @override
  String gridCommitFailed(Object error) {
    return 'Échec de l\'écriture : $error';
  }

  @override
  String get statusBarReady => 'Prêt';

  @override
  String get statusBarExecuting => 'Exécution';

  @override
  String statusBarElapsed(String duration) {
    return 'Temps écoulé $duration';
  }

  @override
  String statusBarLineCol(int line, int column) {
    return 'Ligne $line, Colonne $column';
  }

  @override
  String executionStatusBarRows(int count) {
    return '$count lignes';
  }

  @override
  String get executionStatusBarErrorHint =>
      'Cliquez sur un onglet de résultat pour voir les détails des erreurs';

  @override
  String get toolbarExecutionPlan => 'Plan d\'exécution';

  @override
  String get toolbarFormat => 'Formater';

  @override
  String get toolbarSave => 'Enregistrer';

  @override
  String get splitButton => 'Diviser';

  @override
  String get horizontalSplit => 'Division horizontale';

  @override
  String get verticalSplit => 'Division verticale';

  @override
  String get refreshData => 'Actualiser les données';

  @override
  String get analyzingDatabasePerformance =>
      'Analyse des performances de la base de données...';

  @override
  String get fullTableScanDetected => 'Analyse complète de table détectée';

  @override
  String get fullTableScanDesc =>
      'La requête utilise une analyse complète (type=ALL), index recommandé sur les colonnes WHERE';

  @override
  String get timeThreshold => 'Seuil de temps :';

  @override
  String get searchPlaceholder => 'Rechercher...';

  @override
  String get closeBtn => 'Fermer';

  @override
  String get apiSettingsSavedMsg => 'Paramètres API enregistrés';

  @override
  String get resultsHeaderExport => 'Exporter';

  @override
  String get resultsHeaderSearch => 'Rechercher';

  @override
  String get resultsHeaderClear => 'Effacer';

  @override
  String get resultsHeaderSubmit => 'Soumettre';

  @override
  String get connectionStatusConnected => 'Connecté';

  @override
  String get connectionStatusNotConnected => 'Non connecté';

  @override
  String get selectConnection => 'Sélectionner une connexion...';

  @override
  String get selectDatabase => 'Sélectionner une base de données';

  @override
  String get aiQuickActionOptimizeSql => 'Optimiser SQL';

  @override
  String get aiQuickActionExplainQuery => 'Expliquer la requête';

  @override
  String get aiQuickActionGenerateInsert => 'Générer INSERT';

  @override
  String get aiQuickActionGenerateUpdate => 'Générer UPDATE';

  @override
  String get aiQuickActionGenerateDelete => 'Générer DELETE';

  @override
  String get aiQuickActionCreateTable => 'Créer une table';

  @override
  String get aiQuickActionSecurityCheck => 'Vérification de sécurité';

  @override
  String get aiQuickActionIndexSuggestion => 'Suggestion d\'index';

  @override
  String get aiQuickActionExecutionPlan => 'Plan d\'exécution';

  @override
  String get aiQuickActionQueryHistory => 'Historique des requêtes';

  @override
  String get shortcutCategoryQuery => 'Requête';

  @override
  String get queryCancelled => 'Requête annulée';

  @override
  String queryFailed(Object error) {
    return 'Requête échouée: $error';
  }

  @override
  String querySuccessWithTime(Object count, Object time) {
    return 'Requête réussie, $count lignes retournées (${time}ms)';
  }

  @override
  String get cancelingQuery => 'Annulation de la requête...';

  @override
  String get cancelQueryFailed => 'Échec de l\'annulation de la requête';

  @override
  String get confirmCancelTransaction => 'Confirm Cancel Transaction';

  @override
  String get confirmCancelTransactionMessage =>
      'The current connection has an uncommitted transaction. Canceling the query will disconnect and reconnect, causing the transaction to rollback. Continue?';

  @override
  String get cancel => 'Cancel';

  @override
  String get explainPlanSuccess => 'Plan d\'exécution obtenu avec succès';

  @override
  String explainPlanFailed(Object error) {
    return 'Échec de l\'obtention du plan d\'exécution: $error';
  }

  @override
  String get queryEmptyCannotSave =>
      'Le contenu de la requête est vide, impossible de sauvegarder';

  @override
  String get saveQueryTitle => 'Enregistrer la requête';

  @override
  String get queryName => 'Nom de la requête';

  @override
  String get enterQueryName => 'Entrer le nom de la requête';

  @override
  String get saveQueryHint =>
      'Sera enregistré dans la liste des requêtes sauvegardées (max 20)';

  @override
  String querySaved(Object name) {
    return 'Requête enregistrée: $name';
  }

  @override
  String get saveQueryLimitReached =>
      'Limite d\'enregistrement atteinte (20), veuillez d\'abord supprimer quelques requêtes';

  @override
  String savedQueryNameExists(Object name) {
    return 'Le nom de requête enregistrée \"$name\" existe déjà pour cette connexion';
  }

  @override
  String get sqlFormatted => 'SQL formaté';

  @override
  String get pleaseEnterSqlCode => 'Veuillez entrer le code SQL';

  @override
  String get noConnectedServer => 'Aucun serveur connecté';

  @override
  String get split2Hint => 'Split 2 - Entrer une requête SQL...';

  @override
  String get toolbarClose => 'Fermer';

  @override
  String connectedToServer(Object serverName) {
    return 'Connecté à $serverName';
  }

  @override
  String openTableDataFailed(Object error) {
    return 'Échec de l\'ouverture des données de la table : $error';
  }

  @override
  String queryTable(Object tableName) {
    return 'Interroger $tableName';
  }

  @override
  String openViewFailed(Object error) {
    return 'Échec de l\'ouverture de la vue : $error';
  }

  @override
  String queryView(Object viewName) {
    return 'Interroger $viewName';
  }

  @override
  String openProcedureFailed(Object error) {
    return 'Échec de l\'ouverture de la procédure stockée : $error';
  }

  @override
  String callProcedure(Object procName) {
    return 'Appeler $procName';
  }

  @override
  String get cancelConnection => 'Annuler la connexion';

  @override
  String get deleteConnectionTitle => 'Supprimer la connexion';

  @override
  String deleteConnectionConfirm(Object serverName) {
    return 'Êtes-vous sûr de vouloir supprimer la connexion \"$serverName\" ?';
  }

  @override
  String get refresh => 'Actualiser';

  @override
  String get createNewTable => 'Créer une nouvelle table';

  @override
  String get erDiagram => 'Diagramme ER';

  @override
  String get properties => 'Propriétés';

  @override
  String get exportStructure => 'Exporter la structure';

  @override
  String get dropDatabase => 'Supprimer la base de données';

  @override
  String get confirmDeleteDatabase => 'Supprimer la base de données';

  @override
  String get confirmDropTable => 'Supprimer la table';

  @override
  String typeNameToConfirm(String name) {
    return 'Tapez \"$name\" pour confirmer';
  }

  @override
  String dropDatabaseWarning(String name) {
    return 'La base de données \"$name\" sera définitivement supprimée.';
  }

  @override
  String objectCountWarning(int count, String type) {
    return '$count $type seront détruits';
  }

  @override
  String get allDataWillBeLost => 'Toutes les données seront perdues';

  @override
  String copiedDbStructureToClipboard(Object dbName) {
    return 'Structure de $dbName copiée dans le presse-papiers';
  }

  @override
  String databaseDeleted(Object dbName) {
    return 'Base de données $dbName supprimée';
  }

  @override
  String get browseData => 'Parcourir les données';

  @override
  String get editTable => 'Modifier la table';

  @override
  String get copyTableName => 'Copier le nom de la table';

  @override
  String get copyColumnName => 'Copier le nom de colonne';

  @override
  String get copyIndexName => 'Copier le nom d\'index';

  @override
  String get dropColumn => 'Supprimer la colonne';

  @override
  String get editIndex => 'Modifier l\'index';

  @override
  String get dropIndex => 'Supprimer l\'index';

  @override
  String confirmDropColumn(Object column, Object table) {
    return 'Supprimer la colonne \"$column\" de la table \"$table\" ?';
  }

  @override
  String confirmDropIndex(Object index) {
    return 'Supprimer l\'index \"$index\" ?';
  }

  @override
  String columnDropped(Object column) {
    return 'Colonne \"$column\" supprimée';
  }

  @override
  String indexDropped(Object index) {
    return 'Index \"$index\" supprimé';
  }

  @override
  String dropColumnFailed(Object error) {
    return 'Échec de la suppression de colonne : $error';
  }

  @override
  String dropIndexFailed(Object error) {
    return 'Échec de la suppression d\'index : $error';
  }

  @override
  String get loadingSchema => 'Chargement...';

  @override
  String get noColumns => 'Aucune colonne';

  @override
  String get noIndexes => 'Aucun index';

  @override
  String get noProgrammableObjects =>
      'Ce type de base de données ne supporte pas les objets programmables';

  @override
  String get exportData => 'Exporter les données';

  @override
  String get dataSync => 'Synchronisation des données';

  @override
  String get rename => 'Renommer';

  @override
  String get truncate => 'Vider les données';

  @override
  String get dropTable => 'Supprimer la table';

  @override
  String loadTableStructureFailed(Object error) {
    return 'Échec du chargement de la structure de la table : $error';
  }

  @override
  String get tableNameCopied => 'Nom de la table copié';

  @override
  String copiedTableDataToClipboard(Object tableName) {
    return 'Données de $tableName copiées dans le presse-papiers';
  }

  @override
  String tableRenamedTo(Object newName) {
    return 'Table renommée en $newName';
  }

  @override
  String renameFailed(Object error) {
    return 'Échec du renommage : $error';
  }

  @override
  String tableTruncated(Object tableName) {
    return 'Table $tableName vidée';
  }

  @override
  String truncateFailed(Object error) {
    return 'Échec de la suppression : $error';
  }

  @override
  String tableDeleted(Object tableName) {
    return 'Table $tableName supprimée';
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
  String get hintIndexColumns => 'Ex : id, name';

  @override
  String get pleaseDefineAtLeastOneColumn =>
      'Veuillez définir au moins une colonne';

  @override
  String tableCreated(Object tableName) {
    return 'Table $tableName créée avec succès';
  }

  @override
  String createFailed(Object error) {
    return 'Échec de la création : $error';
  }

  @override
  String get tableModified => 'Table modifiée avec succès';

  @override
  String modifyFailed(Object error) {
    return 'Échec de la modification : $error';
  }

  @override
  String get noInformation => 'Aucune information';

  @override
  String get truncateTableData => 'Vider les données de la table';

  @override
  String get menuCut => 'Couper';

  @override
  String get menuCopy => 'Copier';

  @override
  String get menuPaste => 'Coller';

  @override
  String get menuSelectAll => 'Tout sélectionner';

  @override
  String get menuFormatSql => 'Formater SQL';

  @override
  String get menuExecuteQuery => 'Exécuter la requête';

  @override
  String get commandNewConnection => 'Nouvelle connexion';

  @override
  String get commandNewTab => 'Nouvel onglet';

  @override
  String get commandExecuteQuery => 'Exécuter la requête';

  @override
  String get commandFormatSql => 'Formater SQL';

  @override
  String get commandToggleAiPanel => 'Basculer le panneau IA';

  @override
  String get commandQueryHistory => 'Historique des requêtes';

  @override
  String get commandShortcuts => 'Raccourcis';

  @override
  String get commandSettings => 'Paramètres';

  @override
  String get commandCategoryHistory => 'Historique';

  @override
  String get commandCategoryHelp => 'Aide';

  @override
  String get commandDescNewConnection =>
      'Créer une nouvelle connexion de base de données';

  @override
  String get commandDescNewTab => 'Créer un nouvel onglet de requête';

  @override
  String get commandDescExecuteQuery => 'Exécuter la requête SQL actuelle';

  @override
  String get commandDescFormatSql => 'Formater le code SQL';

  @override
  String get commandDescToggleSidebar =>
      'Afficher ou masquer la barre latérale';

  @override
  String get commandDescToggleAiPanel => 'Afficher ou masquer le panneau IA';

  @override
  String get commandDescQueryHistory => 'Voir l\'historique d\'exécution';

  @override
  String get commandDescShortcuts => 'Voir tous les raccourcis clavier';

  @override
  String get commandDescSettings => 'Ouvrir les paramètres de l\'application';

  @override
  String get searchNavigateKeys => '↑↓/Souris';

  @override
  String get menuConnect => 'Connecter';

  @override
  String get menuCancelConnection => 'Annuler la connexion';

  @override
  String get menuDisconnect => 'Déconnecter';

  @override
  String get menuRefresh => 'Actualiser';

  @override
  String get menuEditConnection => 'Modifier la connexion';

  @override
  String get menuCloneConnection => 'Cloner la connexion';

  @override
  String get menuDeleteConnection => 'Supprimer la connexion';

  @override
  String get addColumn => 'Ajouter une colonne';

  @override
  String get addIndex => 'Ajouter un index';

  @override
  String get noIndexesClickToAdd =>
      'Aucun index, cliquez sur le bouton ci-dessus pour ajouter';

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
      'CSV est un format de feuille de calcul universel, compatible avec Excel, Numbers, Google Sheets, etc.';

  @override
  String get formatJSONDesc =>
      'JSON est un format de données structuré, idéal pour les programmes ou les appels d\'API.';

  @override
  String get formatExcelDesc =>
      'Le format Excel préserve les types de données et le formatage, idéal pour l\'analyse approfondie des données.';

  @override
  String get formatMarkdownDesc =>
      'Le format de tableau Markdown est adapté aux documents, rapports ou révisions de code.';

  @override
  String get formatSqlInsertDesc =>
      'Les instructions SQL INSERT peuvent être directement importées dans d\'autres bases de données, idéales pour la migration des données.';

  @override
  String get copiedToClipboard => 'Copié dans le presse-papiers';

  @override
  String get hintFormatName => 'Ex : Mon format';

  @override
  String get hintOptionalDescription => 'Description optionnelle';

  @override
  String get formatterSelectPreset => 'Sélectionner un préréglage';

  @override
  String get formatterFormat => 'Formater';

  @override
  String get formatterCopyResult => 'Copier le résultat';

  @override
  String get formatterHintInputSql => 'Entrez le code SQL ici...';

  @override
  String get formatterSpace => 'Espace';

  @override
  String get formatterTab => 'Tabulation';

  @override
  String get formatterIndentSize => 'Taille de l\'indentation';

  @override
  String get formatterMaxLineLength => 'Longueur maximale de ligne';

  @override
  String get formatterUppercaseKeywords => 'Mots-clés en majuscules';

  @override
  String get formatterAlignKeywords => 'Aligner les mots-clés';

  @override
  String get formatterPreserveComments => 'Préserver les commentaires';

  @override
  String get formatterNewlineBeforeParentheses =>
      'Nouvelle ligne avant les parenthèses';

  @override
  String get formatterCompactMode => 'Mode compact';

  @override
  String get formatterPosition => 'Position';

  @override
  String get formatterEnd => 'Fin';

  @override
  String get formatterStart => 'Début';

  @override
  String loadFailed(Object error) {
    return 'Échec du chargement';
  }

  @override
  String exportFailed(String error) {
    return 'Échec de l\'exportation : $error';
  }

  @override
  String timeAgoDays(Object count) {
    return '$count jours';
  }

  @override
  String timeAgoHours(Object count) {
    return '$count heures';
  }

  @override
  String timeAgoMinutes(Object count) {
    return '$count minutes';
  }

  @override
  String get timeAgoJustNow => 'À l\'instant';

  @override
  String get optimizationFullTableScan => 'Analyse complète de table';

  @override
  String get optimizationFullTableScanDesc =>
      'La requête utilise une analyse complète de table (type=ALL), un index est recommandé sur les colonnes WHERE';

  @override
  String get optimizationFilesort => 'Tri de fichiers';

  @override
  String get optimizationFilesortDesc =>
      'La requête utilise un tri de fichiers (Using filesort), un index est recommandé sur la colonne ORDER BY';

  @override
  String get optimizationTemporary => 'Table temporaire';

  @override
  String get optimizationTemporaryDesc =>
      'La requête utilise une table temporaire (Using temporary), envisagez d\'optimiser les requêtes GROUP BY ou DISTINCT';

  @override
  String get optimizationLowEfficiency => 'Faible efficacité';

  @override
  String optimizationLowEfficiencyDesc(
    Object ratio,
    Object rowsExamined,
    Object rowsSent,
  ) {
    return 'L\'efficacité d\'analyse de la requête est faible, envisagez d\'ajouter un index';
  }

  @override
  String get optimizationNoIssue => 'Aucun problème';

  @override
  String get optimizationNoIssueDesc =>
      'Le plan d\'exécution de la requête semble normal';

  @override
  String get optimizationSuggestions => 'Suggestions d\'optimisation';

  @override
  String get indexTypeDistribution => 'Distribution des types d\'index';

  @override
  String get noData => 'Aucune donnée';

  @override
  String get indexPrimary => 'Primaire';

  @override
  String get indexUnique => 'Unique';

  @override
  String get indexNormal => 'Normal';

  @override
  String get totalIndexes => 'Total des index';

  @override
  String get indexUsed => 'Utilisé';

  @override
  String get indexUnused => 'Non utilisé';

  @override
  String indexCount(Object count) {
    return 'Nombre d\'index';
  }

  @override
  String columnCardinality(Object cardinality) {
    return 'Cardinalité';
  }

  @override
  String columnsLabel(Object columns) {
    return 'Colonnes';
  }

  @override
  String get totalTables => 'Total des tables';

  @override
  String get totalRows => 'Total des lignes';

  @override
  String get dataSize => 'Taille des données';

  @override
  String get indexSize => 'Taille des index';

  @override
  String get tableSizeDistribution => 'Distribution de la taille des tables';

  @override
  String get tableNameLabel => 'Nom de la table';

  @override
  String get tableEngineLabel => 'Moteur';

  @override
  String get tableRowCountLabel => 'Nombre de lignes';

  @override
  String get tableDataSizeLabel => 'Taille des données';

  @override
  String get tableIndexSizeLabel => 'Taille des index';

  @override
  String get tableTotalSizeLabel => 'Taille totale';

  @override
  String get tableRatioLabel => 'Ratio';

  @override
  String get databasePerformanceReport =>
      'Rapport de performance de la base de données';

  @override
  String databaseLabel(Object name) {
    return 'Base de données';
  }

  @override
  String generatedAtLabel(Object time) {
    return 'Généré le';
  }

  @override
  String get tableCountLabel => 'Nombre de tables';

  @override
  String get slowQueryCountLabel => 'Nombre de requêtes lentes';

  @override
  String get suggestionCountLabel => 'Nombre de suggestions';

  @override
  String impactLevel(Object level) {
    return 'Niveau d\'impact';
  }

  @override
  String get impactHigh => 'Élevé';

  @override
  String get impactMedium => 'Moyen';

  @override
  String get impactLow => 'Faible';

  @override
  String get recommendedAction => 'Action recommandée';

  @override
  String slowQueryTopN(Object count) {
    return 'Top des requêtes lentes';
  }

  @override
  String get largeTableStats => 'Statistiques des grandes tables';

  @override
  String get tabRenameTitle => 'Renommer la requête';

  @override
  String get tabRenameHint => 'Entrer le nom de la requête';

  @override
  String get tabRename => 'Renommer';

  @override
  String get tabClose => 'Fermer';

  @override
  String get tabCloseOthers => 'Fermer les autres';

  @override
  String get tabCloseToRight => 'Fermer à droite';

  @override
  String get tabCloseAll => 'Fermer tout';

  @override
  String get tabDuplicate => 'Dupliquer l\'onglet';

  @override
  String get tabNewTooltip => 'Nouvelle requête (Ctrl+T)';

  @override
  String tabNewQueryTitle(Object count) {
    return 'Requête $count';
  }

  @override
  String get confirm => 'Confirmer';

  @override
  String get copySuffix => '(Copie)';

  @override
  String get triggerTitle => 'Déclencheurs';

  @override
  String triggerFailedToLoad(Object error) {
    return 'Échec du chargement des déclencheurs: $error';
  }

  @override
  String get triggerFailedToLoadDefinition =>
      'Échec du chargement de la définition du déclencheur';

  @override
  String get triggerDeleteTitle => 'Supprimer le déclencheur';

  @override
  String triggerDeleteConfirm(Object name) {
    return 'Êtes-vous sûr de vouloir supprimer le déclencheur \"$name\"?';
  }

  @override
  String triggerDeleted(Object name) {
    return 'Déclencheur \"$name\" supprimé';
  }

  @override
  String triggerDeleteFailed(Object error) {
    return 'Échec de la suppression du déclencheur: $error';
  }

  @override
  String get triggerCannotDisable =>
      'Les déclencheurs MySQL ne peuvent pas être désactivés directement. Utilisez Supprimer pour les retirer.';

  @override
  String get triggerShowList => 'Afficher la liste';

  @override
  String get triggerGroupByTable => 'Grouper par table';

  @override
  String get triggerSearchHint => 'Rechercher des déclencheurs...';

  @override
  String get triggerNoTriggers => 'Aucun déclencheur trouvé';

  @override
  String get triggerCreate => 'Créer un déclencheur';

  @override
  String get triggerViewDefinition => 'Voir la définition';

  @override
  String get triggerCopyName => 'Copier le nom';

  @override
  String triggerCopied(Object name) {
    return '\"$name\" copié dans le presse-papiers';
  }

  @override
  String get triggerNew => 'Nouveau déclencheur';

  @override
  String triggerDefinition(Object name) {
    return 'Déclencheur: $name';
  }

  @override
  String get formatterSqlFormat => 'Format SQL';

  @override
  String get formatterSavePreset => 'Enregistrer le préréglage';

  @override
  String get formatterPresetName => 'Nom du préréglage';

  @override
  String get formatterCustomPreset => 'Préréglage personnalisé';

  @override
  String get formatterBuiltIn => 'Intégré';

  @override
  String get formatterSaveAsPreset =>
      'Enregistrer les paramètres actuels comme préréglage';

  @override
  String get formatterDeletePreset => 'Supprimer le préréglage';

  @override
  String get formatterInput => 'Entrée';

  @override
  String get formatterOptions => 'Options de formatage';

  @override
  String get formatterIndent => 'Indentation';

  @override
  String get formatterKeywords => 'Mots-clés';

  @override
  String get formatterCommaStyle => 'Style de virgule';

  @override
  String get formatterApplyToEditor => 'Appliquer à l\'éditeur';

  @override
  String filterTitle(String columnName) {
    return 'Filtre: $columnName';
  }

  @override
  String get filterEquals => 'égal à';

  @override
  String get filterNotEquals => 'différent de';

  @override
  String get filterContains => 'contient';

  @override
  String get filterNotContains => 'ne contient pas';

  @override
  String get filterGreaterThan => 'supérieur à';

  @override
  String get filterLessThan => 'inférieur à';

  @override
  String get filterIsEmpty => 'est vide';

  @override
  String get filterIsNotEmpty => 'n\'est pas vide';

  @override
  String get filterRegex => 'regex';

  @override
  String get filterValue => 'Valeur';

  @override
  String get filterEnterValue => 'Entrez la valeur du filtre';

  @override
  String get filterCaseSensitive => 'Sensible à la casse';

  @override
  String get filterTimeFilter => 'Filtre temporel';

  @override
  String get filterToday => 'Aujourd\'hui';

  @override
  String get filterLast24Hours => 'Dernières 24 heures';

  @override
  String get filterLast7Days => '7 derniers jours';

  @override
  String get filterLast30Days => '30 derniers jours';

  @override
  String rowCountLabel(Object count) {
    return '$count lignes';
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
  String get aiPanelCustomModel => 'Modèle personnalisé';

  @override
  String get aiPanelBookmarks => 'Signets';

  @override
  String get aiPanelScrollToMessageDeveloping =>
      'Fonction de défilement vers le message en développement';

  @override
  String get aiPanelBranchConversationCreated =>
      'Conversation de branche créée';

  @override
  String get aiPanelNoConnections =>
      'Aucune connexion, veuillez en créer une dans la gestion des connexions';

  @override
  String get aiPanelConversationList => 'Liste des conversations';

  @override
  String get aiPanelSelectConnection => 'Sélectionner une connexion';

  @override
  String get aiPanelNoConnection => 'Aucune connexion';

  @override
  String get aiPanelSelectDatabaseFirst =>
      'Sélectionner d\'abord une connexion';

  @override
  String get aiPanelSelectDatabase => 'Sélectionner une base de données';

  @override
  String get aiPanelAllDatabases => 'Toutes les bases de données';

  @override
  String get aiPanelConnectionFailed => 'Échec de la connexion';

  @override
  String get aiPanelUnknownError => 'Erreur inconnue';

  @override
  String get aiPanelLoadDatabasesFailed =>
      'Échec du chargement des bases de données';

  @override
  String get aiPanelDangerousOperation => 'Opération dangereuse';

  @override
  String get aiPanelOptimizeSql => 'Optimiser SQL';

  @override
  String get aiPanelSecurityAnalysis => 'Analyse de sécurité';

  @override
  String get aiPanelExecutionPlan => 'Plan d\'exécution';

  @override
  String get aiPanelIndexSuggestions => 'Suggestions d\'index';

  @override
  String get aiPanelInputHint =>
      'Veuillez entrer votre question sur la base de données, ex: Comment optimiser cette requête?';

  @override
  String get aiPanelStop => 'Arrêter';

  @override
  String get aiPanelSend => 'Envoyer';

  @override
  String get aiPanelSelectConnectionFirst =>
      'Veuillez d\'abord sélectionner une instance de connexion dans le menu déroulant ci-dessus.';

  @override
  String aiPanelConnectionNotAvailable(Object name) {
    return 'L\'instance de connexion \"$name\" n\'est pas connectée ou non disponible, veuillez d\'abord la connecter.';
  }

  @override
  String get aiPanelTable => 'Table';

  @override
  String get aiPanelDangerousOperationBadge => 'Opération dangereuse';

  @override
  String get aiPanelThinkingProcess => 'Processus de réflexion';

  @override
  String get aiPanelExpandThinking => 'Développer le processus de réflexion';

  @override
  String get aiPanelCollapseThinking => 'Réduire le processus de réflexion';

  @override
  String get aiPanelRenameSession => 'Renommer la conversation';

  @override
  String get aiPanelSessionTitle => 'Titre de la conversation';

  @override
  String get aiPanelDeleteSession => 'Supprimer la conversation';

  @override
  String aiPanelDeleteSessionConfirm(Object name) {
    return 'Êtes-vous sûr de vouloir supprimer \"$name\"?';
  }

  @override
  String get aiPanelRename => 'Renommer';

  @override
  String get aiPanelUnarchive => 'Désarchiver';

  @override
  String get aiPanelArchive => 'Archiver';

  @override
  String get aiPanelSessions => 'Conversations';

  @override
  String get aiPanelSearchSessions => 'Rechercher des conversations';

  @override
  String get aiPanelNoSessions => 'Aucune conversation';

  @override
  String aiPanelArchivedSessions(Object count) {
    return 'Conversations archivées ($count)';
  }

  @override
  String get aiPanelJustNow => 'À l\'instant';

  @override
  String aiPanelMinutesAgo(Object count) {
    return 'Il y a $count minutes';
  }

  @override
  String aiPanelHoursAgo(Object count) {
    return 'Il y a $count heures';
  }

  @override
  String aiPanelDaysAgo(Object count) {
    return 'Il y a $count jours';
  }

  @override
  String get aiPanelSelectProvider => 'Sélectionner un fournisseur';

  @override
  String aiPanelSelectModelCurrent(Object provider) {
    return 'Sélectionner un modèle (Actuel: $provider)';
  }

  @override
  String aiPanelApiConfigCurrent(Object provider) {
    return 'Configuration API (Actuel: $provider)';
  }

  @override
  String get aiPanelModelProviderMismatch =>
      'Le modèle sélectionné n\'appartient pas au fournisseur sélectionné';

  @override
  String get aiPanelAllowSession => 'Autoriser cette session';

  @override
  String get aiPanelNoBookmarks => 'Aucun signet';

  @override
  String get aiPanelClickBookmarkIcon =>
      'Cliquez sur l\'icône de signet d\'un message pour l\'ajouter';

  @override
  String get aiCmdOptimizeSql => 'Optimiser l\'instruction SQL';

  @override
  String get aiCmdExplainQuery => 'Expliquer le plan de requête';

  @override
  String get aiCmdGenerateCrud => 'Générer des instructions CRUD';

  @override
  String get aiCmdAnalyzeTable => 'Analyser la structure de la table';

  @override
  String get aiCmdShowHistory => 'Voir l\'historique des requêtes';

  @override
  String get aiCmdShowBookmarks => 'Voir les signets';

  @override
  String get aiCmdBranchConversation => 'Créer une conversation de branche';

  @override
  String get aiCmdListDatabases => 'List all databases';

  @override
  String get aiCmdListTables => 'List all tables';

  @override
  String get settingsThemeMode => 'Mode du thème';

  @override
  String get settingsThemeColor => 'Couleur d\'accent';

  @override
  String get settingsSystem => 'Système';

  @override
  String get settingsPreview => 'Aperçu';

  @override
  String get settingsPrimaryButton => 'Bouton principal';

  @override
  String get settingsSecondaryButton => 'Bouton secondaire';

  @override
  String get settingsApply => 'Appliquer';

  @override
  String get colorBlue => 'Bleu';

  @override
  String get colorPurple => 'Violet';

  @override
  String get colorGreen => 'Vert';

  @override
  String get colorOrange => 'Orange';

  @override
  String get colorRed => 'Rouge';

  @override
  String get colorCyan => 'Cyan';

  @override
  String get colorPink => 'Rose';

  @override
  String get colorYellow => 'Jaune';

  @override
  String get aiChatPageTitle => 'Assistant IA';

  @override
  String get messageLabelYou => 'Vous';

  @override
  String get messageLabelAi => 'IA';

  @override
  String get messageStatusSending => 'Envoi';

  @override
  String get messageStatusGenerating => 'Génération';

  @override
  String get messageStatusFailed => 'Échoué';

  @override
  String get messageStatusCancelled => 'Annulé';

  @override
  String get messageStatusError => 'Erreur';

  @override
  String get messageStatusThinking => 'Réflexion';

  @override
  String tokenUsagePrompt(int count) {
    return 'Entrée $count';
  }

  @override
  String tokenUsageCompletion(int count) {
    return 'Sortie $count';
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
    return 'Session: Entrée $promptTokens · Sortie $completionTokens · Total $totalTokens';
  }

  @override
  String get messageActionRegenerate => 'Régénérer';

  @override
  String get tooltipCopyCode => 'Copier le code';

  @override
  String get tooltipExecuteCode => 'Exécuter le code';

  @override
  String get messageCopied => 'Copié';

  @override
  String toolCallTitle(String name) {
    return 'Outil: $name';
  }

  @override
  String toolResultTitle(String name) {
    return 'Résultat: $name';
  }

  @override
  String get toolCallCompleted => 'Appelé et terminé';

  @override
  String get toolParamLabel => 'Paramètres';

  @override
  String get toolResultLabel => 'Résultat';

  @override
  String get toolGroupTitle => 'Groupe d\'outils';

  @override
  String toolGroupSummary(int count) {
    return '$count outils exécutés';
  }

  @override
  String toolGroupItemTitle(int index, String name) {
    return 'Outil $index: $name';
  }

  @override
  String get toolNoParams => 'Aucun paramètre';

  @override
  String get aiWelcomeTitle => 'Assistant IA de base de données';

  @override
  String get aiWelcomeDescription =>
      'Je peux vous aider à écrire du SQL, optimiser les requêtes, analyser la structure des tables, vérifier la sécurité ou répondre à toutes les questions sur les bases de données.';

  @override
  String aiConnectedTo(String name) {
    return 'Connecté: $name';
  }

  @override
  String get aiExampleSectionTitle => 'Essayez de me demander';

  @override
  String get aiQuickActionsSectionTitle => 'Actions rapides';

  @override
  String get aiTipQuickSend => 'Ctrl + Entrée pour envoyer';

  @override
  String get aiTipSlashCommands => 'Tapez / pour voir toutes les commandes';

  @override
  String get aiExampleQuestion1 =>
      'Optimiser les performances de cette requête';

  @override
  String get aiExampleQuestion2 => 'Analyser la structure actuelle de la table';

  @override
  String get aiExampleQuestion3 => 'Vérifier la sécurité de ce SQL';

  @override
  String get errorApiKeyRequired => 'Veuillez d\'abord entrer la clé API';

  @override
  String get errorBaseUrlRequired => 'Veuillez d\'abord entrer l\'URL de base';

  @override
  String errorFetchModelsFailed(String error) {
    return 'Échec de la récupération de la liste des modèles: $error';
  }

  @override
  String get tooltipRefreshModels => 'Rafraîchir la liste des modèles';

  @override
  String get labelCustomModelInput => 'Entrer le nom du modèle manuellement';

  @override
  String get tooltipAddModel => 'Ajouter un modèle';

  @override
  String get hintFetchOrInputModel =>
      'Cliquez sur rafraîchir pour récupérer ou entrez le nom du modèle manuellement';

  @override
  String get hintFetchModels =>
      'Cliquez sur rafraîchir pour récupérer la liste des modèles';

  @override
  String get errorSelectModelRequired =>
      'Veuillez sélectionner ou entrer un modèle';

  @override
  String errorSaveFailed(String error) {
    return 'Échec de l\'enregistrement: $error';
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
    return 'Fichier sélectionné : $name';
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
  String get smartImportAiInferringTable =>
      'L\'IA déduit le nom de la table...';

  @override
  String smartImportAiSuggestedTable(String name) {
    return 'L\'IA suggère le nom de table: $name';
  }

  @override
  String get smartImportDoNotImport => 'Ne pas importer';

  @override
  String smartImportTaskDescription(int count, String table) {
    return 'Importer $count vers $table';
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
  String get smartImportAiModel => 'Modèle AI';

  @override
  String get aiPanelFullscreen => 'Plein écran';

  @override
  String get aiPanelExitFullscreen => 'Quitter le plein écran';

  @override
  String get aiPanelOpenInNewQuery => 'Ouvert dans une nouvelle requête';

  @override
  String aiPanelInsertStatementsGenerated(int count, String tableName) {
    return 'L\'IA a généré $count instructions INSERT, prêtes à être insérées dans la table [$tableName].';
  }

  @override
  String get aiPanelSqlPreviewTitle => 'Aperçu SQL (3 premières):';

  @override
  String aiPanelMoreStatements(int count) {
    return '... et $count instructions supplémentaires';
  }

  @override
  String aiAgentToolCallLimitReached(int count) {
    return 'L\'assistant IA a atteint la limite d\'appels d\'outils ($count fois). Veuillez simplifier votre question ou procéder étape par étape.';
  }

  @override
  String get aiAgentMaxIterationsReached =>
      'L\'agent a atteint le nombre maximum d\'itérations et n\'a pas pu terminer la conversation.';

  @override
  String get aiAgentDuplicateQuery =>
      'Cette requête a déjà été exécutée. Veuillez répondre directement sur la base des résultats existants sans répéter la requête.';

  @override
  String aiAgentToolExecutionFailed(String error) {
    return 'Échec de l\'exécution de l\'outil: $error';
  }

  @override
  String aiAgentUnknownTool(String name) {
    return 'Outil inconnu: $name';
  }

  @override
  String aiContextCurrentDatabase(String name) {
    return 'Base de données actuelle: $name';
  }

  @override
  String aiContextCurrentTable(String name) {
    return 'Table actuelle: $name';
  }

  @override
  String aiContextRecentQueries(String queries) {
    return 'Requêtes récentes: $queries';
  }

  @override
  String aiContextGoalSummary(String summary) {
    return 'Résumé de l\'objectif de la session actuelle: $summary';
  }

  @override
  String get taskPanelTitle => 'Tâches';

  @override
  String get taskPanelEmpty => 'Aucune tâche';

  @override
  String get taskPanelEmptyDesc =>
      'Les opérations d\'importation ou d\'exportation apparaîtront ici';

  @override
  String get taskPanelClearCompleted => 'Effacer terminées';

  @override
  String get taskPanelStatusPending => 'En attente';

  @override
  String get taskPanelStatusRunning => 'En cours';

  @override
  String get taskPanelStatusPaused => 'En pause';

  @override
  String get taskPanelStatusCompleted => 'Terminé';

  @override
  String get taskPanelStatusFailed => 'Échoué';

  @override
  String get taskPanelStatusCancelled => 'Annulé';

  @override
  String get taskTypeImport => 'Importation';

  @override
  String get taskTypeExport => 'Exportation';

  @override
  String get taskTypeQuery => 'Requête';

  @override
  String get taskActionCancel => 'Annuler';

  @override
  String get taskActionRetry => 'Réessayer';

  @override
  String get taskActionRemove => 'Supprimer';

  @override
  String get taskActionOpenFolder => 'Ouvrir le dossier';

  @override
  String get taskCreateExportTitle => 'Créer une tâche d\'exportation';

  @override
  String get taskCreateExportFormat => 'Format d\'exportation';

  @override
  String get taskCreateExportPath => 'Chemin de sortie';

  @override
  String get taskCreateExportPathPlaceholder =>
      'Cliquez sur le bouton à droite pour sélectionner l\'emplacement de sauvegarde';

  @override
  String get taskCreateExportPathSelect => 'Sélectionner l\'emplacement';

  @override
  String get taskCreateExportStart => 'Créer la tâche';

  @override
  String get taskValidationPathRequired =>
      'Veuillez sélectionner un chemin de sortie';

  @override
  String get taskValidationPathNotWritable =>
      'Le répertoire n\'est pas accessible en écriture, veuillez choisir un autre emplacement';

  @override
  String get taskValidationPathExists =>
      'Le fichier existe déjà et sera écrasé';

  @override
  String taskStatusBarTasks(int count) {
    return '$count tâches';
  }

  @override
  String taskStatusBarRunning(int count) {
    return '$count en cours';
  }

  @override
  String get taskLogInfo => 'Info';

  @override
  String get taskLogWarning => 'Avertissement';

  @override
  String get taskLogError => 'Erreur';

  @override
  String get taskLogSuccess => 'Succès';

  @override
  String get taskDetailTitle => 'Détails de la tâche';

  @override
  String get taskDetailBasicInfo => 'Informations de base';

  @override
  String get taskDetailStatistics => 'Statistiques d\'exécution';

  @override
  String get taskDetailError => 'Message d\'erreur';

  @override
  String get taskDetailOutputFile => 'Fichier de sortie';

  @override
  String get taskDetailLogs => 'Journaux d\'exécution';

  @override
  String get taskDetailCopied => 'Chemin copié dans le presse-papiers';

  @override
  String get taskPhaseAnalyzing => 'Analyse en cours...';

  @override
  String get taskPhaseQuerying => 'Interrogation des données...';

  @override
  String get taskPhaseFormatting => 'Formatage des données...';

  @override
  String get taskPhaseWriting => 'Écriture du fichier...';

  @override
  String get taskPhaseCompleted => 'Terminé';

  @override
  String get aiExportButtonCreate => 'Créer une tâche d\'exportation';

  @override
  String get aiExportButtonAnalyzing => 'Analyse en cours...';

  @override
  String get aiMessageExportAction => 'Exporter ces données';

  @override
  String get smartImportCreateTask =>
      'Créer une tâche d\'importation en arrière-plan';

  @override
  String get schemaDiffTitle => 'Comparaison & Synchronisation de Schéma';

  @override
  String get schemaDiffMenuItem => 'Comparaison & Synchronisation de Schéma';

  @override
  String get schemaDiffSource => 'Source';

  @override
  String get schemaDiffTarget => 'Cible';

  @override
  String get schemaDiffCompareButton => 'Comparer';

  @override
  String get schemaDiffSelectDatabases =>
      'Sélectionnez les bases source et cible à comparer';

  @override
  String get schemaDiffTabOverview => 'Aperçu';

  @override
  String get schemaDiffTabDetails => 'Détails';

  @override
  String get schemaDiffTabSync => 'Synchronisation';

  @override
  String get sidebarColumns => 'Colonnes';

  @override
  String get sidebarIndexes => 'Index';

  @override
  String get sidebarInsertIntoEditor => 'Insérer dans l\'éditeur';

  @override
  String get sidebarForeignKeys => 'Clés étrangères';

  @override
  String get sidebarCopyIndexName => 'Copier le nom de l\'index';

  @override
  String get sidebarCopyForeignKeyName => 'Copier le nom de la clé étrangère';

  @override
  String get sidebarCopyName => 'Copier le nom';

  @override
  String get sidebarReadOnlyConnection => 'Connexion en lecture seule';

  @override
  String get sidebarCopyColumnName => 'Copier le nom de la colonne';

  @override
  String get sidebarCopyColumnType => 'Copier le type de la colonne';

  @override
  String get sidebarCopyAllColumnNames => 'Copier tous les noms de colonnes';

  @override
  String get sidebarOpenEditorFirst => 'Ouvrez d\'abord un onglet de requête';

  @override
  String get sidebarEvents => 'Événements';

  @override
  String get sidebarProgrammableObjects => 'Objets programmables';

  @override
  String get selectDatabaseHint =>
      'Double-cliquez sur une base de données pour voir ses objets';

  @override
  String get workspaceEmptyTitle => 'Aucune requête ouverte';

  @override
  String get workspaceEmptyHint =>
      'Créez un nouvel onglet de requête pour commencer';

  @override
  String get noSearchResults => 'Aucun résultat correspondant';

  @override
  String get page => 'Page';

  @override
  String get settingsSubscriptionSettings => 'Abonnement';

  @override
  String get settingsFreePlan => 'Gratuit';

  @override
  String get settingsFreePlanDesc =>
      'Vous utilisez actuellement le plan gratuit';

  @override
  String get settingsProActivated => 'Pro activé';

  @override
  String get settingsProActivatedDesc =>
      'Toutes les fonctionnalités Pro sont déverrouillées';

  @override
  String get settingsUpgradeToPro => 'Passer à Pro';

  @override
  String get settingsRestorePurchases => 'Restaurer les achats';

  @override
  String get purchaseDialogTitle => 'Passer à Pro';

  @override
  String get purchaseDialogDesc =>
      'Débloquez toutes les fonctionnalités premium avec un abonnement Pro';

  @override
  String get purchaseDialogNoProducts => 'Aucun produit disponible';

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
  String get recentTables => 'Récents';

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
  String get unsavedChangesTitle => 'Modifications non enregistrées';

  @override
  String get unsavedChangesMessage =>
      'Cet onglet contient des modifications non enregistrées. Fermer sans enregistrer ?';

  @override
  String get discardChanges => 'Ignorer';

  @override
  String tabCloseConfirmMessage(String title) {
    return 'Voulez-vous enregistrer les modifications apportées à « $title » avant de fermer ?';
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
  String get exportConnectionsTitle => 'Exporter les connexions';

  @override
  String get importConnectionsTitle => 'Importer les connexions';

  @override
  String get exportConnectionsCount => 'Connexions à exporter';

  @override
  String get exportPasswordHint => 'Mot de passe de sauvegarde';

  @override
  String get confirmExportPasswordHint =>
      'Confirmer le mot de passe de sauvegarde';

  @override
  String get passwordsDoNotMatch => 'Les mots de passe ne correspondent pas';

  @override
  String get importPasswordHint => 'Mot de passe de sauvegarde';

  @override
  String get selectExportFile => 'Enregistrer dans un fichier';

  @override
  String get selectImportFile => 'Sélectionner le fichier de sauvegarde';

  @override
  String selectImportFileFailed(String error) {
    return 'Échec de la sélection du fichier : $error';
  }

  @override
  String get conflictStrategyLabel => 'Si le nom de connexion existe déjà';

  @override
  String get conflictStrategySkip => 'Ignorer';

  @override
  String get conflictStrategyRename => 'Renommer';

  @override
  String get conflictStrategyOverwrite => 'Écraser';

  @override
  String get exportSuccess => 'Connexions exportées avec succès';

  @override
  String get importSuccess => 'Connexions importées avec succès';

  @override
  String get invalidPassword => 'Mot de passe invalide';

  @override
  String get invalidFile => 'Fichier de sauvegarde invalide ou corrompu';

  @override
  String get noConnectionsToExport => 'Aucune connexion à exporter';

  @override
  String get exportThisConnection => 'Exporter cette connexion';

  @override
  String get commandCategoryTools => 'Outils';

  @override
  String get passwordRequiredTitle => 'Mot de passe requis';

  @override
  String passwordRequiredMessage(String serverName) {
    return 'Entrez le mot de passe pour $serverName pour vous connecter';
  }

  @override
  String get connectionConnectNoPassword => 'Se connecter sans mot de passe';

  @override
  String get embeddedRequiresRemoteServer => 'Serveur distant uniquement';

  @override
  String get serverSessionExpiredTitle => 'Session expirée';

  @override
  String get serverSessionExpiredMessage =>
      'Votre session serveur a expiré ou a été révoquée. Veuillez vous reconnecter.';

  @override
  String get serverSessionRelogin => 'Se reconnecter';

  @override
  String get serverReconnectLastSession => 'Revenir au dernier serveur';

  @override
  String get serverReconnectFailed =>
      'La session enregistrée n\'est plus valide. Veuillez vous reconnecter.';

  @override
  String sidebarEmptyTableFailed(String error) {
    return 'Failed to empty table: $error';
  }

  @override
  String sidebarDropViewFailed(String error) {
    return 'Échec de la suppression de la vue : $error';
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
    return 'Voulez-vous vraiment supprimer la vue « $viewName » ?\n\nCette action est irréversible.';
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
  String get sidebarBrowseData => 'Parcourir les données';

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
  String get connectionMongoMode => 'Mode de connexion';

  @override
  String get connectionMongoModeDirect => 'Direct (hôte unique)';

  @override
  String get connectionMongoModeReplicaSet => 'Replica Set';

  @override
  String get connectionMongoSeedHosts => 'Hôtes d\'amorçage';

  @override
  String get connectionMongoSeedHostsHint =>
      'Listez tous les membres du replica set (host:port, un par ligne). Le pilote détecte le primary automatiquement ; cette liste fait foi.';

  @override
  String get connectionMongoSeedHostsRequired =>
      'Au moins un hôte d\'amorçage (host:port) est requis';

  @override
  String get connectionMongoReplicaSetName => 'Nom du Replica Set';

  @override
  String get connectionMongoReplicaSetNameRequired =>
      'Le nom du Replica Set est requis';

  @override
  String get connectionMongoModeAdvanced => 'Avancé (chaîne de connexion)';

  @override
  String get connectionMongoModeSharded => 'Shardé (mongos)';

  @override
  String get connectionMongoMongosHosts => 'Routeurs mongos';

  @override
  String get connectionMongoMongosHostsHint =>
      'Listez tous les routeurs mongos (host:port, un par ligne). Le pilote se connecte via mongos ; le sharding est transparent.';

  @override
  String get connectionMongoMongosHostsRequired =>
      'Au moins un routeur mongos (host:port) est requis';

  @override
  String get connectionMongoInvalidHostPort =>
      'Entrée invalide (host ou host:port attendu)';

  @override
  String get connectionMongoConnectionString => 'Chaîne de connexion';

  @override
  String get connectionMongoConnectionStringHint =>
      'Collez une chaîne de connexion complète (mongodb:// ou mongodb+srv://, incl. Atlas). Les identifiants sont automatiquement retirés ; le mot de passe est chiffré séparément.';

  @override
  String get connectionMongoConnectionStringRequired =>
      'Veuillez coller une chaîne de connexion';

  @override
  String get connectionMongoConnectionStringInvalid =>
      'Chaîne de connexion invalide (doit commencer par mongodb:// ou mongodb+srv://)';

  @override
  String get connInvalidPort => 'Invalid port';

  @override
  String get connUsernameRequired => 'Le nom d\'utilisateur est requis';

  @override
  String get connNameRequired => 'Le nom de la connexion est requis';

  @override
  String get connHostRequired => 'L\'hôte est requis';

  @override
  String get connPortRequired => 'Le port est requis';

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
    return 'Échec de la suppression : $error';
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
  String get bottomPanelTabHistory => 'Historique';

  @override
  String get bottomPanelTabTasks => 'Tâches';

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
  String get dmlCriticalTitle => 'Opération Critique';

  @override
  String get dmlHighWarningTitle => 'Opération à Haut Risque';

  @override
  String get dmlHighWarningBody =>
      'Cette opération affectera toutes les lignes correspondantes. Envisagez d\'ajouter une clause LIMIT.';

  @override
  String get dmlAddLimit => 'Ajouter LIMIT';

  @override
  String get dmlConfirmExecute => 'Confirmer l\'exécution';

  @override
  String get dmlRiskSummary => 'Résumé des risques';

  @override
  String get dmlStatementsToExecute => 'Instructions à exécuter :';

  @override
  String dmlEstimatedAffectedRows(Object count) {
    return 'Lignes affectées estimées : $count';
  }

  @override
  String dmlSqlInjectionDetail(Object details) {
    return 'Injection SQL : $details';
  }

  @override
  String get dmlTriggerDeleteWithoutWhere => 'DELETE sans clause WHERE';

  @override
  String get dmlTriggerUpdateWithoutWhere => 'UPDATE sans clause WHERE';

  @override
  String get dmlTriggerDropTable => 'Opération DROP TABLE';

  @override
  String get dmlTriggerDropDatabase => 'Opération DROP DATABASE';

  @override
  String get dmlTriggerTruncateTable => 'Opération TRUNCATE TABLE';

  @override
  String get dmlTriggerDmlWithoutLimit => 'DML sans clause LIMIT';

  @override
  String get dmlTriggerAlterDropColumn => 'ALTER TABLE DROP COLUMN';

  @override
  String get dmlTriggerSqlInjection => 'Modèle d\'injection SQL détecté';

  @override
  String dropTableDeleteConfirmBody(Object tableName) {
    return 'Voulez-vous vraiment supprimer la table \"$tableName\" ?';
  }

  @override
  String get dropTableDeleteImpact =>
      'Cette opération est irréversible. Toutes les données de la table seront définitivement supprimées.';

  @override
  String get dropTableCheckingDependencies => 'Vérification des dépendances...';

  @override
  String get dropTableDependencyWarning => 'Avertissement de dépendance';

  @override
  String get connectionReadOnlyMode => 'Mode lecture seule';

  @override
  String get connectionReadOnlyModeDesc =>
      'Interdire les opérations INSERT/UPDATE/DELETE/DDL';

  @override
  String get connectionSshHost => 'Hôte SSH';

  @override
  String get connectionSshUsername => 'Nom d\'utilisateur SSH';

  @override
  String get connectionSshPassword => 'Mot de passe SSH';

  @override
  String get connSshHostRequired => 'L\'hôte SSH est requis';

  @override
  String get commonNavigate => 'Naviguer';

  @override
  String get resultsSqlStatementLabel => 'Instruction SQL :';

  @override
  String get resultsExecutionSuccess => 'Exécution réussie';

  @override
  String resultsAffectedRows(Object count) {
    return '$count lignes affectées';
  }

  @override
  String resultsElapsedMs(Object ms) {
    return 'Durée : $ms ms';
  }

  @override
  String resultsFilterConditions(Object count) {
    return 'Filtre : $count conditions';
  }

  @override
  String resultsShowingRows(Object filtered, Object total) {
    return '$filtered / $total lignes affichées';
  }

  @override
  String get resultsClearFilter => 'Effacer les filtres';

  @override
  String get resultsNoDataGuidance =>
      'Écrivez une requête dans l\'éditeur et appuyez sur Ctrl+Entrée (ou F5) pour l\'exécuter';

  @override
  String get queryHistoryEmptyHint =>
      'Exécutez une requête avec Ctrl+Entrée ou F5 — elle apparaîtra ici automatiquement';

  @override
  String get safetyExplainWarning => 'Avertissement de performance';

  @override
  String safetyExplainFullScan(Object rows) {
    return 'Analyse complète de table détectée. Estimation de $rows lignes.';
  }

  @override
  String get safetyExecuteAnyway => 'Exécuter quand même';

  @override
  String get safetyCancelAndOptimize => 'Annuler et voir le plan d\'exécution';

  @override
  String get safetyPreflightTimeout =>
      'Vérification préliminaire expirée. Analyse de performance ignorée.';

  @override
  String get dmlAuditBlocked => 'Opération DML bloquée';

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
  String get processManagerTitle => 'Gestionnaire de processus';

  @override
  String get processListNoProcesses => 'No active processes';

  @override
  String get processListNoQueryText => 'Aucun texte de requête';

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
  String get mongoNodeReplication => 'Réplication';

  @override
  String get mongoNodeSharding => 'Sharding';

  @override
  String get mongoValidationRules => 'Règles de validation';

  @override
  String get mongoReplicationStandalone =>
      'Autonome - ne fait pas partie d\'un réplica set';

  @override
  String get mongoShardingNotSharded => 'Pas un cluster sharding';

  @override
  String get mongoValidationNoRules => 'Aucune règle de validation';

  @override
  String get resultColumnTruncated =>
      'La valeur peut être tronquée (type d\'objet volumineux)';

  @override
  String get dorisUpdateGuardMessage =>
      'Les tables Doris en modèle Duplicate/Aggregate ne prennent pas en charge UPDATE ; seuls les modèles Unique/Primary Key le font.';

  @override
  String get dorisTableModelLabel => 'Modèle de table';

  @override
  String get dorisModelDuplicate => 'Duplicate';

  @override
  String get dorisModelUnique => 'Unique';

  @override
  String get dorisModelPrimaryKey => 'Primary Key';

  @override
  String get dorisHashColumnLabel => 'Colonne de hachage';

  @override
  String get dorisBucketsLabel => 'Buckets';

  @override
  String get dorisModelNeedsKeyColumn =>
      'Ce modèle nécessite au moins une colonne clé (cochez Primary Key sur une colonne)';

  @override
  String get dorisAggregateFunctionLabel => 'Fonction d\'agrégation';

  @override
  String get dorisModelAggregate => 'Aggregate';

  @override
  String get dorisPartitionColumn => 'Colonne de partition';

  @override
  String get dorisPartitionName => 'Nom de partition';

  @override
  String get dorisPartitionLessThan => 'Valeurs inférieures à';

  @override
  String get dorisAddPartition => 'Ajouter une partition';

  @override
  String get offlineLicenseTitle => 'Licence hors ligne';

  @override
  String get offlineLicensePurchaseHint =>
      'Pour passer à Pro : scannez le code de paiement sur notre page GitHub/Gitee, puis envoyez votre code machine et la capture du paiement à l\'auteur. Vous recevrez une licence à importer ci-dessous.';

  @override
  String get machineCodeLabel => 'Code machine';

  @override
  String get machineCodeUnavailable =>
      'Impossible de lire le code machine sur cet appareil';

  @override
  String get importLicense => 'Importer une licence';

  @override
  String get importLicenseHint =>
      'Collez la chaîne de licence ou choisissez un fichier .dbmlicense';

  @override
  String get buyLicense => 'Acheter une licence';

  @override
  String get machineCodeCopied => 'Code machine copié dans le presse-papiers';

  @override
  String get licenseFilePick => 'Choisir un fichier';

  @override
  String get licenseTypeYearly => 'Abonnement annuel';

  @override
  String get licenseTypeLifetime => 'À vie';

  @override
  String licenseExpiresAt(String date) {
    return 'Expire : $date';
  }

  @override
  String get removeLicense => 'Retirer la licence';

  @override
  String get licenseImportSuccess =>
      'Licence activée — fonctionnalités Pro débloquées';

  @override
  String get licenseErrorInvalid => 'Format de licence invalide';

  @override
  String get licenseErrorSignature =>
      'Échec de la vérification de la signature';

  @override
  String get licenseErrorMachine =>
      'Cette licence est liée à une autre machine';

  @override
  String get licenseErrorExpired => 'Cette licence a expiré';

  @override
  String get licenseErrorNoMachine =>
      'Code machine illisible ; licence hors ligne indisponible sur cet appareil';

  @override
  String licenseActiveInfo(String email) {
    return 'Licencié à $email';
  }

  @override
  String get errorCopy => 'Copier';

  @override
  String get errorCopied => 'Copié';

  @override
  String get errorAnalyzeWithAi => 'Analyser avec l\'IA';

  @override
  String trialRemaining(int count, String feature) {
    return '$count essais restants pour $feature';
  }

  @override
  String trialUsedUp(String feature) {
    return 'Essai $feature épuisé';
  }

  @override
  String get centerTitle => 'Centre d\'exécution';

  @override
  String get centerTabTasks => 'Tâches';

  @override
  String get centerTabErrors => 'Erreurs';

  @override
  String get centerClearErrors => 'Effacer les erreurs';

  @override
  String get centerDismissError => 'Masquer';

  @override
  String get aiPromptErrorHeader =>
      'Diagnostiquez cette erreur de base de données : expliquez la cause et proposez une correction.';

  @override
  String get commonUndo => 'Annuler';

  @override
  String commonDeleteWithCount(Object count) {
    return 'Supprimer ($count)';
  }

  @override
  String aiPanelSessionsDeletedCount(Object count) {
    return '$count conversations supprimées';
  }

  @override
  String aiPanelSessionDeleted(Object title) {
    return '« $title » supprimée';
  }

  @override
  String get aiPanelSelectDatabaseRequired =>
      'Veuillez d\'abord sélectionner une base de données dans la liste déroulante ci-dessus.';

  @override
  String get aiPanelMongoExecutionPlan => '🔍 Plan d\'exécution Mongo';

  @override
  String get aiPanelSelectSessions => 'Sélectionner les sessions';

  @override
  String get aiPanelExportTaskCreated => 'Tâche d\'export créée avec succès';

  @override
  String get aiPanelDdlOperationCancelled =>
      'Opération DDL annulée par l\'utilisateur.';

  @override
  String get aiAssistantOpenTooltip => 'Ouvrir l\'assistant IA';

  @override
  String get schemaImpactRiskLow => 'Risque faible';

  @override
  String get schemaImpactRiskMedium => 'Risque moyen';

  @override
  String get schemaImpactRiskHigh => 'Risque élevé';

  @override
  String get schemaImpactRiskCritical => 'Risque critique';

  @override
  String get schemaImpactTitle => 'Analyse d\'impact sur la structure';

  @override
  String schemaImpactSubtitle(Object table, Object type) {
    return '$type sur `$table`';
  }

  @override
  String get schemaImpactDataLossWarning =>
      'Risque de perte de données : cette opération supprimera définitivement les données.';

  @override
  String schemaImpactAffectedObjects(Object count) {
    return 'Objets affectés ($count)';
  }

  @override
  String schemaImpactWarnings(Object count) {
    return 'Avertissements ($count)';
  }

  @override
  String get schemaImpactRecommendations => 'Recommandations';

  @override
  String get schemaImpactHideRollbackScript =>
      'Masquer le script de restauration';

  @override
  String get schemaImpactShowRollbackScript =>
      'Afficher le script de restauration';

  @override
  String get schemaImpactNoRollbackAvailable =>
      'Aucune restauration disponible';

  @override
  String get schemaImpactRollbackCaveat =>
      'Le rollback auto-généré est une ébauche best-effort - les types de colonnes et contraintes peuvent être inexacts. Vérifiez avant l\'exécution ; les données ne peuvent pas être récupérées automatiquement.';

  @override
  String get schemaImpactBackupRequired =>
      'Sauvegarde des données requise avant la restauration';

  @override
  String get schemaImpactConfirmationRequired =>
      'Cette opération requiert votre confirmation explicite avant exécution.';

  @override
  String get ddlConfirmDialogTitle => 'Confirmation DDL requise';

  @override
  String ddlAffectedObjectsCount(Object count) {
    return 'Objets affectés ($count)';
  }

  @override
  String get ddlExecuteButton => 'Exécuter le DDL';

  @override
  String get ddlSqlStatementLabel => 'Instruction SQL :';

  @override
  String ddlRiskLevelLabel(Object level) {
    return 'Niveau de risque : $level';
  }

  @override
  String get ddlDataLossRiskDetected => 'Risque de perte de données détecté';

  @override
  String ddlWarningsCount(Object count) {
    return 'Avertissements ($count)';
  }

  @override
  String get ddlTypeConfirmationToProceed =>
      'Saisir la confirmation pour continuer';

  @override
  String ddlTypeToConfirmDestructive(Object token) {
    return 'Saisissez « $token » pour confirmer cette opération destructive :';
  }

  @override
  String get commonUnknown => 'Inconnu';

  @override
  String get commonDismiss => 'Fermer';

  @override
  String get readOnlyModeBlocked =>
      'Cette connexion est en mode lecture seule ; les opérations d\'écriture sont désactivées.';

  @override
  String get dlgFillVariables => 'Renseigner les variables';

  @override
  String dlgVariableRequired(String variable) {
    return 'Veuillez saisir $variable';
  }

  @override
  String get dlgEditTrigger => 'Modifier le trigger';

  @override
  String get dlgCreateTrigger => 'Créer un trigger';

  @override
  String triggerLoadTablesFailed(String error) {
    return 'Échec du chargement des tables : $error';
  }

  @override
  String get triggerSelectTableRequired => 'Veuillez sélectionner une table';

  @override
  String get triggerSelectEventRequired =>
      'Veuillez sélectionner au moins un événement';

  @override
  String get triggerUpdated => 'Trigger mis à jour avec succès';

  @override
  String get triggerCreated => 'Trigger créé avec succès';

  @override
  String triggerSaveFailed(String error) {
    return 'Échec de l\'enregistrement du trigger : $error';
  }

  @override
  String get triggerNameLabel => 'Nom du trigger';

  @override
  String get triggerNameRequired => 'Le nom du trigger est requis';

  @override
  String get triggerNameInvalid => 'Format de nom de trigger invalide';

  @override
  String get triggerTimingLabel => 'Timing';

  @override
  String get triggerEventLabel => 'Événement';

  @override
  String get triggerTableLabel => 'Table';

  @override
  String get triggerSelectTableHint => 'Sélectionner une table';

  @override
  String get triggerBodyLabel => 'Corps du trigger';

  @override
  String get triggerBodyHint =>
      'Saisissez le corps du trigger (instructions SQL)\nExemple :\nSET NEW.updated_at = NOW();';

  @override
  String triggerCount(int count) {
    return '$count triggers';
  }

  @override
  String get dlgExecutionResult => 'Résultat de l\'exécution';

  @override
  String dlgExecuteRoutine(String type) {
    return 'Exécuter $type';
  }

  @override
  String dlgRoutineName(String name) {
    return 'Nom : $name';
  }

  @override
  String dlgRoutineType(String type) {
    return 'Type : $type';
  }

  @override
  String dlgRoutineReturnType(String type) {
    return 'Type de retour : $type';
  }

  @override
  String get dlgParameters => 'Paramètres';

  @override
  String get dlgRoutineNoParams =>
      'Cette procédure/fonction ne nécessite aucun paramètre';

  @override
  String get dlgOutputParam => 'Paramètre de sortie';

  @override
  String get dlgReturnValueLabel => 'Valeur de retour :';

  @override
  String dlgRowsAffected(int count) {
    return 'Lignes affectées : $count';
  }

  @override
  String dlgEditRoutine(String type) {
    return 'Modifier $type';
  }

  @override
  String routineParameterCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count paramètres',
      one: '1 paramètre',
      zero: 'Aucun paramètre',
    );
    return '$_temp0';
  }

  @override
  String routineDeleteConfirmation(String type, String name) {
    return 'Supprimer $type \"$name\" ?';
  }

  @override
  String get routineListTitle => 'Procédures & Fonctions';

  @override
  String routineDefinitionTitle(String type) {
    return 'Définition $type';
  }

  @override
  String get queryExecutionPlan => 'Plan d\'exécution de requête';

  @override
  String dlgCreateRoutine(String type) {
    return 'Créer $type';
  }

  @override
  String get dlgNameRequired => 'Le nom est requis';

  @override
  String get dlgRoutineNameInvalid =>
      'Le nom ne peut contenir que des lettres, des chiffres et des underscores, et ne peut pas commencer par un chiffre';

  @override
  String get dlgReturnTypeRequired => 'Veuillez sélectionner un type de retour';

  @override
  String get dlgSqlCode => 'Code SQL';

  @override
  String get dlgRoutineProcedure => 'Procédure stockée';

  @override
  String get dlgRoutineFunction => 'Fonction';

  @override
  String get commonUpdate => 'Mettre à jour';

  @override
  String get commonCreate => 'Créer';

  @override
  String get auditLogTitle => 'Journal d\'audit des requêtes';

  @override
  String get auditLogAllStatus => 'Tous les statuts';

  @override
  String get auditLogAll => 'Tous';

  @override
  String get auditLogTime => 'Heure';

  @override
  String get auditLogDuration => 'Durée';

  @override
  String get auditLogRows => 'Lignes';

  @override
  String get auditLogStatus => 'Statut';

  @override
  String get auditLogEmpty => 'Aucun journal d\'audit pour le moment';

  @override
  String get auditLogEmptyHint =>
      'Exécutez des requêtes pour commencer à enregistrer des journaux';

  @override
  String get auditLogTotal => 'Total';

  @override
  String get auditLogWrite => 'Écriture';

  @override
  String get auditLogAvgTime => 'Temps moyen';

  @override
  String get auditLogClearTitle => 'Effacer les journaux d\'audit';

  @override
  String get auditLogClearConfirm =>
      'Voulez-vous vraiment effacer tous les journaux d\'audit ? Cette action est irréversible.';

  @override
  String get auditLogClear => 'Effacer';

  @override
  String get piiMaskingTitle => 'Masquage des données PII';

  @override
  String get piiMaskingEnable => 'Activer le masquage PII';

  @override
  String get piiMaskingEnableDesc =>
      'Masquer automatiquement les données sensibles dans les résultats de requête';

  @override
  String get piiMaskingTypes => 'Types de données sensibles';

  @override
  String get piiTypeEmail => 'Adresses e-mail';

  @override
  String get piiTypePhone => 'Numéros de téléphone';

  @override
  String get piiTypeIdCard => 'Cartes d\'identité';

  @override
  String get piiTypeCreditCard => 'Cartes de crédit';

  @override
  String get piiTypeBankCard => 'Comptes bancaires';

  @override
  String get piiTypePassword => 'Mots de passe';

  @override
  String get piiTypeIpAddress => 'Adresses IP';

  @override
  String get shortcutNoMatching => 'Aucun raccourci correspondant';

  @override
  String get shortcutPressEscToClose => 'Appuyez sur ÉCHAP pour fermer';

  @override
  String get indexTypePrimary => 'Primaire';

  @override
  String get performanceAnalyzerWeeklyReportTitle =>
      'Rapports hebdomadaires de requêtes lentes';

  @override
  String get performanceAnalyzerWeeklyReportDesc =>
      'Recevez chaque lundi le top 10 des requêtes lentes avec analyse EXPLAIN';

  @override
  String get performanceAnalyzerLearnMore => 'En savoir plus';

  @override
  String get backupListLoading => 'Chargement de la liste des sauvegardes...';

  @override
  String dbPropertiesTitle(String name) {
    return 'Propriétés de la base de données - $name';
  }

  @override
  String get dbPropertyName => 'Nom';

  @override
  String get dbPropertyCharset => 'Jeu de caractères';

  @override
  String get dbPropertyCollation => 'Collation';

  @override
  String get dbPropertySize => 'Taille';

  @override
  String get dbPropertyTableCount => 'Tables';

  @override
  String get dbPropertyViewCount => 'Vues';

  @override
  String get dbPropertyRoutineCount => 'Procédures/Fonctions';

  @override
  String get exportFormatLabel => 'Format d\'export';

  @override
  String exportRowCount(int count) {
    return '$count lignes au total';
  }

  @override
  String get taskCreateExportFilter => 'Filtre';

  @override
  String get taskCreateExportEstRows => 'Lignes estimées';

  @override
  String get taskCreateExportValidating => 'Validation...';

  @override
  String get taskCreateExportSaveDialogTitle =>
      'Sélectionner l\'emplacement d\'enregistrement du fichier d\'export';

  @override
  String taskValidationPathNotExists(String path) {
    return 'Le répertoire n\'existe pas : $path';
  }

  @override
  String taskCreateExportDesc(String table) {
    return 'Exporter $table';
  }

  @override
  String taskCreateExportDescFiltered(String table) {
    return 'Exporter $table (filtré)';
  }

  @override
  String get sqliteConnectionEditTitle => 'Modifier la connexion SQLite';

  @override
  String get sqliteConnectionNewTitle => 'Nouvelle connexion SQLite';

  @override
  String get createSuperTableTitle => 'Créer une supertable';

  @override
  String get importWizardTitle => 'Assistant d\'import de données';

  @override
  String dbCreateSuccess(String name) {
    return 'Base de données « $name » créée avec succès';
  }

  @override
  String get dbCreateFailed => 'Échec de la création de la base de données';

  @override
  String dbCreateError(String error) {
    return 'Erreur : $error';
  }

  @override
  String get dbOperationCannotBeUndone => 'Cette opération est irréversible !';

  @override
  String dropTablePermanentWarning(String table) {
    return 'La table « $table » et toutes ses données seront définitivement supprimées.';
  }

  @override
  String get dropTableDataLossWarning =>
      'Cette opération est irréversible ! Toutes les données de cette table seront définitivement perdues.';

  @override
  String get objectTypeTable => 'table';

  @override
  String get objectTypeView => 'vue';

  @override
  String get commonRemove => 'Retirer';

  @override
  String get commonRequired => 'Requis';

  @override
  String get commonInvalidIdentifier => 'Identifiant invalide';

  @override
  String get mongoValidationJsonObject => 'Le JSON doit être un objet';

  @override
  String mongoValidationInvalidJson(String error) {
    return 'JSON invalide : $error';
  }

  @override
  String get settingsAutoLimitEnabledDesc =>
      'Ajouter automatiquement LIMIT aux requêtes SELECT';

  @override
  String get sqliteConnectionInfo => 'Informations de connexion';

  @override
  String get sqliteNameHint => 'Ma base SQLite';

  @override
  String get connectionDirNotExists => 'Le répertoire n\'existe pas';

  @override
  String get indexSelectColumnRequired =>
      'Veuillez sélectionner au moins une colonne';

  @override
  String indexCreateFailed(String error) {
    return 'Échec de la création de l\'index : $error';
  }

  @override
  String indexUpdateFailed(String error) {
    return 'Échec de la mise à jour de l\'index : $error';
  }

  @override
  String get indexNameRequired => 'Le nom de l\'index est requis';

  @override
  String get superTableTags => 'Tags';

  @override
  String get superTableCreated => 'Supertable créée avec succès';

  @override
  String get redisLibNameCodeRequired =>
      'Le nom de la bibliothèque et le code sont requis';

  @override
  String get redisAdapterNotAvailable => 'Adaptateur Redis non disponible';

  @override
  String get redisLibraryCreated =>
      'Bibliothèque de fonctions créée avec succès';

  @override
  String redisLibraryCreateFailed(String error) {
    return 'Échec de la création de la bibliothèque : $error';
  }

  @override
  String get redisLibraryUsageHint => 'Utilisé dans #!lua name=<library>';

  @override
  String get redisInsertExample => 'Insérer un exemple';

  @override
  String get redisCreateLibrary => 'Créer la bibliothèque';

  @override
  String redisKeyLoadFailed(String error) {
    return 'Échec du chargement des données de la clé : $error';
  }

  @override
  String get redisKeyUpdated => 'Clé mise à jour avec succès';

  @override
  String redisKeySaveFailed(String error) {
    return 'Échec de l\'enregistrement de la clé : $error';
  }

  @override
  String get redisKeySaveChanges => 'Enregistrer les modifications';

  @override
  String get serverConnectTitle => 'Se connecter au serveur';

  @override
  String get serverConnectUrl => 'URL du serveur';

  @override
  String get serverUrlRequired => 'L\'URL du serveur est requise';

  @override
  String get serverUrlInvalid => 'URL invalide (ex. https://myserver:3000)';

  @override
  String get serverConnectEmail => 'E-mail';

  @override
  String get serverEmailRequired => 'L\'e-mail est requis';

  @override
  String get serverEmailInvalid => 'E-mail invalide';

  @override
  String get serverPasswordRequired => 'Le mot de passe est requis';

  @override
  String get mongoValidationFixErrors =>
      'Veuillez corriger les erreurs JSON avant d\'appliquer';

  @override
  String get mongoValidationApplied =>
      'Règles de validation appliquées avec succès';

  @override
  String get mongoValidationRemoved => 'Règles de validation supprimées';

  @override
  String get mongoValidationLevel => 'Niveau de validation';

  @override
  String get mongoValidationAction => 'Action de validation';

  @override
  String mongoValidationApplyFailed(String error) {
    return 'Échec de l\'application des règles de validation : $error';
  }

  @override
  String get indexSelectColumns => 'Sélectionner les colonnes';

  @override
  String get redisLibraryTitle => 'Créer une bibliothèque de fonctions';

  @override
  String get redisLibraryNameLabel => 'Nom de la bibliothèque';

  @override
  String get redisLibraryCreateFailedSyntax =>
      'Échec de la création de la bibliothèque (nécessite Redis 7.0+, vérifiez la syntaxe)';

  @override
  String get redisLuaCodeLabel => 'Code Lua';

  @override
  String get redisReplaceExisting =>
      'Remplacer la bibliothèque existante du même nom (FUNCTION LOAD REPLACE)';

  @override
  String get redisLibraryInfoText =>
      'Le nom de la bibliothèque est écrit automatiquement dans le shebang #!lua. Le code Lua doit contenir des appels redis.register_function(). N\'écrivez pas le shebang vous-même.';

  @override
  String get superTableCreateFailed => 'Échec de la création de la supertable';

  @override
  String get superTableColumns => 'Colonnes';

  @override
  String get errorTitle => 'Une erreur est survenue';

  @override
  String get errorDescriptionLabel => 'Détails de l\'erreur :';

  @override
  String get errorStackLabel => 'Trace d\'exécution :';

  @override
  String get columnFilterTypeNumeric => 'Numérique';

  @override
  String get columnFilterTypeDateTime => 'Date/Heure';

  @override
  String get columnFilterTypeText => 'Texte';

  @override
  String get columnFilterPlaceholderNumeric => 'Entrez un nombre';

  @override
  String get columnFilterPlaceholderDateTime =>
      'Entrez une date (ex. 2024-01-01)';

  @override
  String get columnFilterPlaceholderText => 'Entrez du texte';

  @override
  String columnFilterFor(String columnName) {
    return 'Filtre : $columnName';
  }

  @override
  String columnFilterActive(int count) {
    return '$count conditions de filtre actives';
  }

  @override
  String columnFilterRowCount(String filtered, String total) {
    return '$filtered / $total lignes';
  }

  @override
  String get filterOpEquals => 'égal à';

  @override
  String get filterOpNotEquals => 'différent de';

  @override
  String get filterOpContains => 'contient';

  @override
  String get filterOpNotContains => 'ne contient pas';

  @override
  String get filterOpStartsWith => 'commence par';

  @override
  String get filterOpEndsWith => 'se termine par';

  @override
  String get filterOpGreaterThan => 'supérieur à';

  @override
  String get filterOpGreaterThanOrEqual => 'supérieur ou égal à';

  @override
  String get filterOpLessThan => 'inférieur à';

  @override
  String get filterOpLessThanOrEqual => 'inférieur ou égal à';

  @override
  String get filterOpBetween => 'entre';

  @override
  String get filterOpIsNull => 'est null';

  @override
  String get filterOpIsNotNull => 'n\'est pas null';

  @override
  String get filterOpIsEmpty => 'est vide';

  @override
  String get filterOpIsNotEmpty => 'n\'est pas vide';

  @override
  String get tableNoData => 'Aucune donnée';

  @override
  String tableRowCountTotal(String count) {
    return '$count lignes au total';
  }

  @override
  String get tableLargeDatasetHint =>
      '(Grand jeu de données, faites défiler pour charger)';

  @override
  String tableRowRange(String start, String end, String total) {
    return '$start-$end / $total lignes';
  }

  @override
  String get importWizStepSelectFile => 'Sélectionner le fichier';

  @override
  String get importWizStepAnalyzeFile => 'Analyser le fichier';

  @override
  String get importWizStepColumnMapping => 'Correspondance des colonnes';

  @override
  String get importWizStepPreviewPII => 'Aperçu et PII';

  @override
  String get importWizStepConfirmImport => 'Confirmer l\'importation';

  @override
  String importWizStepOf(String current, String total, String title) {
    return 'Étape $current sur $total : $title';
  }

  @override
  String get importWizTargetDatabase => 'Base de données cible';

  @override
  String get importWizSelectDatabase => 'Sélectionner une base de données';

  @override
  String get importWizTargetTableOptional => 'Table cible (facultatif)';

  @override
  String get importWizLetAiInfer =>
      '-- Laisser l\'IA déduire le nom de la table --';

  @override
  String get importWizChooseFile =>
      'Cliquez pour sélectionner un fichier ou glissez ici';

  @override
  String get importWizChangeFile => 'Changer de fichier';

  @override
  String get importWizSupportedFormats =>
      'Prend en charge les formats CSV, JSON, Excel, TSV';

  @override
  String get importWizFileUnknown => 'Inconnu';

  @override
  String get importWizAiAnalyzing => 'L\'IA analyse le fichier...';

  @override
  String get importWizDetectingFormat =>
      'Détection du format, de l\'encodage, des types de champs...';

  @override
  String get importWizFileAnalysisResult => 'Résultat de l\'analyse du fichier';

  @override
  String get importWizFormat => 'Format';

  @override
  String get importWizEncoding => 'Encodage';

  @override
  String get importWizFieldCount => 'Champs';

  @override
  String get importWizEstimatedRows => 'Lignes est.';

  @override
  String get importWizFileSize => 'Taille du fichier';

  @override
  String get importWizDelimiter => 'Délimiteur';

  @override
  String get importWizDetectedFields => 'Champs détectés';

  @override
  String get importWizAiSuggestion => 'Suggestion de l\'IA';

  @override
  String importWizTargetTableName(String tableName) {
    return 'Table cible : $tableName';
  }

  @override
  String get importWizNoAnalysisResult => 'Aucun résultat d\'analyse';

  @override
  String get importWizSelectFileFirst =>
      'Veuillez d\'abord sélectionner un fichier';

  @override
  String get importWizNoColumnMapping => 'Aucune correspondance de colonnes';

  @override
  String get importWizGeneratingMapping => 'Génération de la correspondance...';

  @override
  String get importWizColumnMappingConfig =>
      'Configuration de la correspondance';

  @override
  String importWizColumnsMapped(String mapped, String total) {
    return '$mapped/$total colonnes associées';
  }

  @override
  String get importWizMappingDescription =>
      'Associez les colonnes du fichier aux colonnes de la table. Sélectionnez \"Ignorer\" pour sauter une colonne.';

  @override
  String get importWizFileColumn => 'Colonne fichier';

  @override
  String get importWizDatabaseColumn => 'Colonne base de données';

  @override
  String get importWizType => 'Type';

  @override
  String get importWizPiiDetection => 'Détection de données sensibles PII';

  @override
  String get importWizPiiDetectionMessage =>
      'Les champs sensibles suivants ont été détectés. Veuillez confirmer si vous souhaitez continuer l\'importation :';

  @override
  String get importWizPiiAcknowledge =>
      'Je comprends, continuer l\'importation';

  @override
  String get importWizDataPreview => 'Aperçu des données';

  @override
  String importWizWarnings(String count) {
    return '$count avertissements';
  }

  @override
  String importWizFirstRows(String count) {
    return '$count premières lignes';
  }

  @override
  String get importWizSensitiveField => 'Champ sensible';

  @override
  String get importWizDataValidationWarnings =>
      'Avertissements de validation des données';

  @override
  String importWizValidationRowFormat(String row, String col, String msg) {
    return 'Ligne $row, Col $col : $msg';
  }

  @override
  String get importWizImportSummary =>
      'Résumé de la configuration d\'importation';

  @override
  String get importWizSummaryTargetDatabase => 'Base de données cible';

  @override
  String get importWizSummaryTargetTable => 'Table cible';

  @override
  String get importWizSummaryFile => 'Fichier';

  @override
  String get importWizSummaryMappedColumns => 'Colonnes associées';

  @override
  String get importWizSummaryDataRows => 'Lignes de données';

  @override
  String get importWizConflictStrategy =>
      'Stratégie de résolution des conflits';

  @override
  String get importWizConflictSkip => 'Ignorer les doublons';

  @override
  String get importWizConflictSkipDesc =>
      'Si une clé en double est trouvée, ignorer la ligne et continuer l\'importation';

  @override
  String get importWizConflictUpdate => 'Mettre à jour les lignes existantes';

  @override
  String get importWizConflictUpdateDesc =>
      'Si une clé en double est trouvée, mettre à jour les données existantes';

  @override
  String get importWizConflictAbort => 'Annuler l\'importation';

  @override
  String get importWizConflictAbortDesc =>
      'Si une clé en double est trouvée, arrêter immédiatement l\'importation';

  @override
  String get importWizConflictSkipName => 'Skip duplicates';

  @override
  String get importWizConflictUpdateName => 'Update existing';

  @override
  String get importWizConflictAbortName => 'Abort';

  @override
  String get importWizImporting => 'Importation en cours...';

  @override
  String importWizRowsProgress(String imported, String total) {
    return '$imported/$total lignes';
  }

  @override
  String importWizFailedRows(String count) {
    return 'Échec : $count lignes';
  }

  @override
  String get importWizImportComplete => 'Importation terminée !';

  @override
  String importWizImportFailed(String error) {
    return 'Échec de l\'importation : $error';
  }

  @override
  String importWizImportSuccessMsg(String count) {
    return '$count lignes importées avec succès';
  }

  @override
  String get importWizImportErrorMsg =>
      'Une erreur est survenue lors de l\'importation';

  @override
  String get importWizPreviousStep => 'Précédent';

  @override
  String get importWizClose => 'Fermer';

  @override
  String get importWizStartImport => 'Démarrer l\'importation';

  @override
  String get importWizNextStep => 'Suivant';

  @override
  String get importWizReimport => 'Réimporter';

  @override
  String importWizLoadDatabasesFailed(String error) {
    return 'Échec du chargement de la liste des bases de données : $error';
  }

  @override
  String importWizLoadTablesFailed(String error) {
    return 'Échec du chargement de la liste des tables : $error';
  }

  @override
  String importWizPickFileFailed(String error) {
    return 'Échec de la sélection du fichier : $error';
  }

  @override
  String importWizAnalysisFailed(String error) {
    return 'Échec de l\'analyse : $error';
  }

  @override
  String importWizMappingFailed(String error) {
    return 'Échec de la génération de la correspondance : $error';
  }

  @override
  String get importWizFileAnalysisFailed => 'Échec de l\'analyse du fichier';

  @override
  String get importWizImportFailedGeneric => 'Échec de l\'importation';

  @override
  String get importWizNotSelected => 'Non sélectionné';

  @override
  String get importWizNotSet => 'Non défini';

  @override
  String get importWizUnknown => 'Inconnu';

  @override
  String get importWizPiiDetectionSummary => 'Détection PII';

  @override
  String importWizSensitiveFieldCount(String count) {
    return '$count champs sensibles';
  }

  @override
  String get smartImportAnalyzingDetail =>
      'L\'IA identifie les types de champs et génère l\'instruction CREATE TABLE';

  @override
  String get smartImportColumnMapping => 'Correspondance des colonnes';

  @override
  String smartImportColumnsMapped(String mapped, String total) {
    return '$mapped/$total colonnes associées';
  }

  @override
  String get smartImportFileColumn => 'Colonne fichier';

  @override
  String get smartImportTableColumn => 'Colonne table';

  @override
  String get smartImportConflictResolution => 'Résolution des conflits';

  @override
  String get smartImportDataPreview => 'Aperçu des données';

  @override
  String smartImportFirstRows(String count) {
    return '$count premières lignes';
  }

  @override
  String get smartImportBack => 'Retour';

  @override
  String get smartImportBackgroundTask => 'Importation en arrière-plan';

  @override
  String get smartImportFailedToGenerateSql =>
      '-- Échec de la génération de l\'instruction CREATE TABLE';

  @override
  String smartImportTargetTableSelected(String table) {
    return 'Table cible sélectionnée : $table';
  }

  @override
  String smartImportTargetTableEntered(String table) {
    return 'Table cible saisie : $table';
  }

  @override
  String smartImportAnalysisFailed(String error) {
    return 'Échec de l\'analyse du fichier : $error';
  }

  @override
  String smartImportColumnMappingsComplete(String mapped, String total) {
    return 'Correspondance terminée : $mapped/$total colonnes associées automatiquement';
  }

  @override
  String smartImportPiiDetected(String types) {
    return 'Détection PII : Champs sensibles trouvés - $types';
  }

  @override
  String get smartImportPiiNone =>
      'Détection PII : Aucun champ sensible trouvé';

  @override
  String smartImportPiiFailed(String error) {
    return 'Échec de la détection PII : $error';
  }

  @override
  String smartImportPreviewGenerated(String count) {
    return 'Aperçu des données généré ($count lignes)';
  }

  @override
  String smartImportPreviewFailed(String error) {
    return 'Échec de la génération de l\'aperçu : $error';
  }

  @override
  String smartImportMappingFailed(String error) {
    return 'Échec de la génération de la correspondance : $error';
  }

  @override
  String importServiceStartImport(String table) {
    return 'Démarrage de l\'importation vers la table \"$table\"...';
  }

  @override
  String importServiceColumnMapping(String mapped, String total) {
    return 'Correspondance : $mapped/$total colonnes associées';
  }

  @override
  String importServiceConflictStrategy(String strategy) {
    return 'Stratégie de conflit : $strategy';
  }

  @override
  String get importServiceImporting => 'Démarrage de l\'importation...';

  @override
  String importServiceBatchSuccess(String batch, String count) {
    return 'Lot $batch : $count lignes importées avec succès';
  }

  @override
  String importServiceBatchInsertFailed(String count) {
    return 'Échec de l\'importation par lot ($count lignes), tentative ligne par ligne...';
  }

  @override
  String importServiceUpdateFailed(String error) {
    return 'Échec de la mise à jour : $error';
  }

  @override
  String importServiceDataTooLong(String row) {
    return 'Ligne $row données trop longues, ignorée';
  }

  @override
  String importServiceRowInsertFailed(String row, String error) {
    return 'Ligne $row échec de l\'insertion : $error';
  }

  @override
  String importServiceBatchSkipped(String count) {
    return 'Lot ignoré : $count lignes (doublons)';
  }

  @override
  String importServiceBatchUpdated(String count) {
    return 'Lot mis à jour : $count lignes';
  }

  @override
  String importServiceBatchFailed(String count) {
    return 'Lot échoué : $count lignes';
  }

  @override
  String importServicePhaseProgress(
    String imported,
    String skipped,
    String updated,
  ) {
    return '$imported lignes importées, $skipped ignorées, $updated mises à jour...';
  }

  @override
  String get importServiceImportCancelled => 'Importation annulée';

  @override
  String importServiceFileReadFailed(String error) {
    return 'Échec de la lecture du fichier : $error';
  }

  @override
  String importServiceImportComplete(String imported, String failed) {
    return 'Importation terminée ! Succès : $imported lignes, Échec : $failed lignes';
  }

  @override
  String taskExecutorAnalyzeFile(String path) {
    return 'Analyse du fichier : $path';
  }

  @override
  String taskExecutorFileFormat(String format, String encoding, String rows) {
    return 'Format : $format, Encodage : $encoding, Lignes est. : $rows';
  }

  @override
  String get taskExecutorTableNotExists =>
      'La table n\'existe pas, création en cours...';

  @override
  String get taskExecutorTableCreated => 'Table créée avec succès';

  @override
  String get taskExecutorTableCreateFailed =>
      'Échec de la création de la table';

  @override
  String taskExecutorTableNotExistsError(String table) {
    return 'La table cible \"$table\" n\'existe pas. Veuillez d\'abord créer la table.';
  }

  @override
  String get taskExecutorNoColumnMapping =>
      'Aucune correspondance de colonnes utilisable. Vérifiez que les champs du fichier correspondent aux champs de la table.';

  @override
  String taskExecutorColumnMapping(String mapped, String total) {
    return 'Correspondance : $mapped/$total colonnes associées';
  }

  @override
  String get taskExecutorStartImport => 'Démarrage de l\'importation...';

  @override
  String taskExecutorImportComplete(String imported, String failed) {
    return 'Importation terminée ! Succès : $imported lignes, Échec : $failed lignes';
  }

  @override
  String get taskExecutorImportFinished => 'Importation terminée';

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
  String get viewModeTable => 'Tableau';

  @override
  String get viewModeChart => 'Graphique';

  @override
  String get viewModeCard => 'Carte';

  @override
  String get viewModeDocument => 'Documents';

  @override
  String get viewModeJsonTree => 'Arborescence JSON';

  @override
  String get viewModeKeyValue => 'Clé-Valeur';

  @override
  String get documentExpand => 'Déplier';

  @override
  String get documentCollapse => 'Replier';

  @override
  String documentExpandMore(int count) {
    return 'Déplier $count champs de plus';
  }

  @override
  String jsonTreeItemCount(int count) {
    return '$count éléments';
  }

  @override
  String get keyValueField => 'Champ';

  @override
  String get keyValueValue => 'Valeur';

  @override
  String keyValueFieldLabel(String field) {
    return 'Champ : $field';
  }

  @override
  String keyValueLengthLabel(int length) {
    return 'Longueur : $length caractères';
  }

  @override
  String get chartViewComingSoon => 'Vue graphique (bientôt)';

  @override
  String chartExportSuccess(String path) {
    return 'Graphique enregistré sous $path';
  }

  @override
  String chartExportFailed(String error) {
    return 'Échec de l\'export du graphique : $error';
  }

  @override
  String chartSamplingNotice(int count) {
    return 'Grand jeu de données : $count points échantillonnés';
  }

  @override
  String get chartAiTrend => 'Analyse de tendance IA';

  @override
  String get chartTypeLine => 'Ligne';

  @override
  String get chartTypeBar => 'Barre';

  @override
  String get chartTypePie => 'Camembert';

  @override
  String get chartTypeScatter => 'Nuage';

  @override
  String get statisticsPanelTitle => 'Statistiques';

  @override
  String get exportStepBack => 'Précédent';

  @override
  String get exportStepNext => 'Suivant';

  @override
  String get noJsonDataToSample => 'Aucune donnée à échantillonner';

  @override
  String get noLeafNodes => 'Aucun champ extractible';

  @override
  String get fieldNotInAllRows => 'absent de certaines lignes';

  @override
  String get commonRetry => 'Reessayer';

  @override
  String get extensionNoAdapter => 'Pas d\'adaptateur';

  @override
  String get extensionNotPostgres => 'Pas une connexion PostgreSQL';

  @override
  String get extensionLoadFailed => 'Echec du chargement des membres';

  @override
  String get extensionTypes => 'Types';

  @override
  String get extensionFunctions => 'Fonctions';

  @override
  String get extensionOperators => 'Operateurs';

  @override
  String get extensionSchema => 'Schema';

  @override
  String get extensionDescription => 'Description';

  @override
  String get vectorLoadFailed => 'Echec du chargement des index vectoriels';

  @override
  String get vectorNoAdapter => 'Pas d\'adaptateur';

  @override
  String get vectorNoIndexes => 'Aucun index vectoriel defini';

  @override
  String get jsonInvalidJson => 'JSON invalide';

  @override
  String get jsonNoMatches => 'Aucune correspondance';

  @override
  String get jsonSearchHint => 'Rechercher cles ou valeurs...';

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
  String get mcpTokensMenuLabel => 'Jetons MCP';

  @override
  String get mcpTokensTitle => 'Jetons MCP';

  @override
  String get mcpTokensIntro =>
      'Jetons durables pour les clients IA (Claude Code, Cursor). Collez-en un comme Bearer token dans la configuration MCP du client ; révocable à tout moment.';

  @override
  String get mcpTokensNotConnected =>
      'Connectez-vous à un serveur DbMaster pour gérer les jetons MCP.';

  @override
  String get mcpTokensEmpty =>
      'Aucun jeton pour l\'instant. Créez-en un pour votre client IA.';

  @override
  String get mcpTokensNameHint => 'Nom du jeton (ex. claude-code-mac)';

  @override
  String get mcpTokensCreate => 'Créer';

  @override
  String mcpTokensOnceTitle(String name) {
    return 'Jeton « $name » créé';
  }

  @override
  String get mcpTokensOnceWarning =>
      'Copiez-le maintenant — pour des raisons de sécurité, il ne sera plus jamais affiché. Utilisez-le comme Bearer token dans la configuration de votre client MCP (ex. mcp.json).';

  @override
  String get mcpTokensCopy => 'Copier';

  @override
  String get mcpTokensCopied => 'Jeton copié dans le presse-papiers';

  @override
  String get mcpTokensDone => 'Terminé';

  @override
  String mcpTokensLastUsed(String value) {
    return 'Dernière utilisation : $value';
  }

  @override
  String get mcpTokensNeverUsed => 'jamais';

  @override
  String get mcpTokensRevoke => 'Révoquer';

  @override
  String get mcpTokensRevokeTitle => 'Révoquer ce jeton ?';

  @override
  String mcpTokensRevokeBody(String name, String prefix) {
    return 'Les clients utilisant « $name » ($prefix…) cesseront immédiatement de fonctionner. Action irréversible.';
  }

  @override
  String get serverConnectionsMenuLabel => 'Connexions du serveur';

  @override
  String get serverConnectionsTitle => 'Connexions du serveur';

  @override
  String get serverConnectionsIntro =>
      'Connexions de base de données enregistrées sur le serveur. La synchronisation de données, les contrôles de santé et les approbations DDL s\'exécutent sur celles-ci ; la barre latérale du bureau est distincte.';

  @override
  String get serverConnectionsNotConnected => 'Non connecté à un serveur.';

  @override
  String get serverConnectionsEmpty =>
      'Aucune connexion serveur pour le moment. Ajoutez-en une pour que les tâches de synchronisation / contrôle de santé / approbation aient une base de données.';

  @override
  String get serverConnectionsAdd => 'Ajouter';

  @override
  String get serverConnectionsEdit => 'Modifier';

  @override
  String get serverConnectionsDelete => 'Supprimer';

  @override
  String get serverConnectionsKindCollab => 'collab';

  @override
  String get serverConnectionsKindSourceDrift => 'source drift (lecture seule)';

  @override
  String get serverConnectionsDeleteTitle => 'Supprimer la connexion';

  @override
  String serverConnectionsDeleteBody(String name) {
    return 'Supprimer la connexion serveur « $name » ?';
  }

  @override
  String serverConnectionsDeleteTaskWarning(num count) {
    return '$count tâche(s) référencent cette connexion et seront supprimées (comme source) ou détachées (comme cible).';
  }

  @override
  String get serverConnFormCreateTitle => 'Ajouter une connexion serveur';

  @override
  String get serverConnFormEditTitle => 'Modifier la connexion serveur';

  @override
  String get serverConnFormName => 'Nom';

  @override
  String get serverConnFormType => 'Type';

  @override
  String get serverConnFormHost => 'Hôte';

  @override
  String get serverConnFormPort => 'Port';

  @override
  String get serverConnFormUsername => 'Nom d\'utilisateur';

  @override
  String get serverConnFormPassword => 'Mot de passe';

  @override
  String get serverConnFormPasswordKeepHint =>
      'Laisser vide pour conserver le mot de passe stocké';

  @override
  String get serverConnFormDatabase =>
      'Base de données par défaut (facultatif)';

  @override
  String get serverConnFormSqlitePath => 'Chemin du fichier de base de données';

  @override
  String get serverConnFormSave => 'Enregistrer';

  @override
  String get serverConnFormRequired => 'Obligatoire';

  @override
  String get serverConnFormInvalidPort => 'Le port doit être un nombre';

  @override
  String get dataSyncConnectionNotOnServer =>
      'La connexion sélectionnée n\'est pas enregistrée sur le serveur. Ajoutez-la d\'abord dans « Connexions du serveur », puis réessayez.';

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
    return 'Fourni par $plugin';
  }

  @override
  String get connectionDbIndex => 'Index de base de données';

  @override
  String get connectionAuthDatabase => 'Base de données d\'authentification';

  @override
  String get connectionRedisAuthNone => 'Aucune authentification';

  @override
  String get connectionRedisAuthNoneDesc => 'Aucune authentification requise';

  @override
  String get connectionRedisAuthPasswordOnly => 'Mot de passe seul';

  @override
  String get connectionRedisAuthPasswordOnlyDesc =>
      'Mot de passe AUTH (Redis < 6.0)';

  @override
  String get connectionRedisAuthUsernamePassword =>
      'Nom d\'utilisateur + mot de passe (ACL)';

  @override
  String get connectionRedisAuthUsernamePasswordDesc =>
      'AUTH nom d\'utilisateur mot de passe (Redis 6.0+ ACL)';

  @override
  String get connectionSshAuthPassword => 'Mot de passe';

  @override
  String get connectionSshAuthPrivateKey => 'Clé privée';

  @override
  String get sidebarCapabilityTitle => 'Capacités';

  @override
  String get sidebarCapGroupDatabaseObjects => 'Objets de base de données';

  @override
  String get sidebarCapGroupAdvanced => 'Avancé';

  @override
  String get redisCapGroupKeyspace => 'Espace de clés';

  @override
  String get redisCapWorkbench => 'Workbench en ligne de commande';

  @override
  String get redisCapPubsub => 'Pub/Sub';

  @override
  String get redisCapLua => 'Scripts Lua';

  @override
  String get redisCapPipeline => 'Pipeline';

  @override
  String get redisCapTransaction => 'Transaction';

  @override
  String get redisCapMemoryAnalysis => 'Analyse mémoire';

  @override
  String get redisCapKeyspaceNotifications => 'Notifications d\'espace de clés';

  @override
  String get redisCapAcl => 'Gestion des ACL';

  @override
  String get redisCapConfig => 'Modifier la configuration';

  @override
  String get mongoValidationTitle => 'Règles de validation';

  @override
  String get mongoValidationNoValidator =>
      'Cette collection n\'a aucune règle de validation configurée (à ajouter via collMod ou le shell MongoDB).';

  @override
  String mongoValidationLoadFailed(String error) {
    return 'Échec du chargement des règles de validation : $error';
  }

  @override
  String sidebarDocumentInserted(String collection) {
    return 'Document inséré dans $collection';
  }

  @override
  String get aiSkillCatalogTitle => 'Compétences';

  @override
  String get aiSkillGroupSql => 'SQL';

  @override
  String get aiSkillGroupData => 'Données';

  @override
  String get aiSkillGroupSchema => 'Schéma';

  @override
  String get aiSkillGroupOps => 'Ops';

  @override
  String get aiSkillNl2sqlName => 'Langage naturel vers SQL';

  @override
  String get aiSkillNl2sqlDesc =>
      'Décrivez ce que vous voulez et obtenez du SQL';

  @override
  String get aiSkillSqlExplainName => 'Explication SQL';

  @override
  String get aiSkillSqlExplainDesc =>
      'Expliquez ce que fait une instruction SQL';

  @override
  String get aiSkillSqlExplainPrompt =>
      'Expliquez pas à pas ce que fait cette instruction SQL :\n```\n\n```';

  @override
  String get aiSkillQueryOptimizerName => 'Optimisation de requête';

  @override
  String get aiSkillQueryOptimizerDesc =>
      'Analysez une requête lente et proposez des optimisations';

  @override
  String get aiSkillQueryOptimizerPrompt =>
      'Analysez les problèmes de performance de cette requête et proposez des optimisations :\n```\n\n```';

  @override
  String get aiSkillDataCleaningName => 'Conseils de nettoyage de données';

  @override
  String get aiSkillDataCleaningDesc =>
      'Proposez des étapes pour nettoyer les données sales';

  @override
  String get aiSkillDataCleaningPrompt =>
      'Proposez des étapes de nettoyage pour les données sales de ma table. Problèmes connus :';

  @override
  String get aiSkillImportMappingName => 'Mapping d’import';

  @override
  String get aiSkillImportMappingDesc =>
      'Générez un mapping de colonnes pour l’import de données';

  @override
  String get aiSkillImportMappingPrompt =>
      'Générez un mapping de colonnes (JSON) pour importer le fichier suivant dans la table.\nColonnes source :\nColonnes cible :';

  @override
  String get aiSkillSchemaAnalysisName => 'Analyse de schéma';

  @override
  String get aiSkillSchemaAnalysisDesc =>
      'Examinez le schéma actuel et signalez les risques';

  @override
  String get aiSkillSchemaAnalysisPrompt =>
      'Examinez le schéma de la base actuelle et signalez les risques de conception et les améliorations.';

  @override
  String get aiSkillSchemaDiffName => 'Assistant de comparaison de schéma';

  @override
  String get aiSkillSchemaDiffDesc =>
      'Comparez deux définitions de schéma et produisez un diff';

  @override
  String get aiSkillSchemaDiffPrompt =>
      'Comparez les deux définitions de schéma suivantes et produisez un diff unifié :\n<schema-a>\n\n</schema-a>\n<schema-b>\n\n</schema-b>';

  @override
  String get aiSkillIndexSuggestName => 'Conseils d’index';

  @override
  String get aiSkillIndexSuggestDesc =>
      'Proposez des index pour une requête ou une table';

  @override
  String get aiSkillIndexSuggestPrompt =>
      'Proposez des index pour cette requête et justifiez :\n```\n\n```';

  @override
  String get aiSkillErrorDiagnosisName => 'Diagnostic d’erreur';

  @override
  String get aiSkillErrorDiagnosisDesc =>
      'Diagnostiquez un message d’erreur de base de données';

  @override
  String get aiSkillErrorDiagnosisPrompt =>
      'Diagnostiquez cette erreur de base de données et proposez des correctifs :\n```\n\n```';

  @override
  String get aiSkillSlowQueryName => 'Analyse de requêtes lentes';

  @override
  String get aiSkillSlowQueryDesc =>
      'Analysez les entrées du journal de requêtes lentes';

  @override
  String get aiSkillSlowQueryPrompt =>
      'Analysez cette entrée du journal de requêtes lentes et localisez le goulot d’étranglement :\n```\n\n```';

  @override
  String get aiContextPanelTitle => 'Contexte';

  @override
  String get aiContextConnectionSection => 'Connexion actuelle';

  @override
  String get aiContextDatabaseSection => 'Base de données actuelle';

  @override
  String get aiContextNoConnection => 'Aucune connexion sélectionnée';

  @override
  String get aiContextSchemaContext => 'Inclure le contexte du schéma';

  @override
  String get aiContextSchemaContextDesc =>
      'Joindre les schémas des tables de la base actuelle lors de l’envoi';

  @override
  String get aiPanelOpenSkillCatalog => 'Catalogue de compétences';

  @override
  String get aiPanelOpenContextPanel => 'Panneau de contexte';

  @override
  String get safetyBannerAddLimit => 'Ajouter LIMIT';

  @override
  String safetyBannerCooldown(int seconds) {
    return 'Confirmer (${seconds}s)';
  }

  @override
  String get safetyDmlAllRowsWarning =>
      'Cette opération affectera toutes les lignes correspondantes. Envisagez d\'ajouter une clause LIMIT.';

  @override
  String get safetySeverityHigh => 'Élevé';

  @override
  String get safetySeverityMedium => 'Avertissement';

  @override
  String get safetySeverityLow => 'Info';

  @override
  String get safetySeverityPolicy => 'Stratégie';

  @override
  String gateTitleSingle(int count) {
    return 'Confirmation d\'exécution : $count risque(s) dans ce SQL';
  }

  @override
  String gateTitleMulti(int count, int total) {
    return 'Confirmation d\'exécution : $count risque(s) sur $total instructions';
  }

  @override
  String get gateDdlImpactTitle => 'Analyse d\'impact DDL';

  @override
  String gateStatementLabel(int n) {
    return 'Instruction $n';
  }

  @override
  String get gateSuggestionLabel => 'Correction suggérée';

  @override
  String gateOverview(int total, int high, int medium, int low, int ok) {
    return '$total instructions · Élevé $high · Avertissement $medium · Info $low · OK $ok';
  }

  @override
  String gateSkipHighRisk(int skip, int exec) {
    return 'Ignorer $skip à haut risque, exécuter $exec';
  }

  @override
  String get gateAllHighDisabled => 'Tous à haut risque — rien à exécuter';

  @override
  String get gateApplySuggestions => 'Appliquer les suggestions';

  @override
  String get gateProceed => 'Exécuter quand même';

  @override
  String get gateProceedAll => 'Tout exécuter quand même';

  @override
  String get gateCancelAll => 'Tout annuler';

  @override
  String get settingsNavAppearance => 'Apparence';

  @override
  String get settingsNavAi => 'IA';

  @override
  String get settingsNavQuery => 'Requêtes';

  @override
  String get settingsNavLanguage => 'Langue';

  @override
  String get settingsNavSecurity => 'Sécurité';

  @override
  String get settingsNavAbout => 'À propos';

  @override
  String get piiExportStepFormat => 'Format';

  @override
  String get piiExportStepScan => 'Analyse PII';

  @override
  String get piiExportStepConfirm => 'Confirmer';

  @override
  String get piiExportNoPiiTitle => 'Aucune donnée PII détectée';

  @override
  String get piiExportNoPiiSubtitle =>
      'Toutes les colonnes seront exportées telles quelles';

  @override
  String piiExportDetectedCount(int count) {
    return '$count colonnes contenant des PII détectées';
  }

  @override
  String get piiExportHighSensitivity => '(haute sensibilité)';

  @override
  String get piiExportKeep => 'Conserver';

  @override
  String get piiExportMask => 'Masquer';

  @override
  String get piiExportHash => 'Hacher';

  @override
  String get piiExportDrop => 'Supprimer la colonne';

  @override
  String get piiExportReadyTitle => 'Prêt à exporter';

  @override
  String get piiExportSummaryFormat => 'Format';

  @override
  String get piiExportSummaryRows => 'Lignes';

  @override
  String get piiExportSummaryPiiColumns => 'Colonnes PII traitées';

  @override
  String get piiExportFootnote =>
      'Les colonnes PII seront traitées selon l\'action choisie ; les colonnes non PII seront exportées telles quelles';

  @override
  String get serverBarNotConnected => 'Non connecté';

  @override
  String get serverBarConnecting => 'Connexion…';

  @override
  String get serverBarLocal => 'Local';

  @override
  String get serverBarConnected => 'Connecté';

  @override
  String get serverBarReconnecting => 'Reconnexion…';

  @override
  String serverBarReconnectingIn(int seconds) {
    return 'Reconnexion dans $seconds s…';
  }

  @override
  String serverBarServerUrl(String url) {
    return 'Serveur : $url';
  }

  @override
  String get serverBarDisconnect => 'Déconnecter';

  @override
  String get serverBarUnknownUser => 'Inconnu';

  @override
  String get serverConnectUnexpectedError =>
      'Une erreur inattendue s\'est produite.';

  @override
  String get cellViewerCopy => 'Copier';

  @override
  String cellViewerChars(Object count) {
    return '$count caractères';
  }

  @override
  String get slowQueryMenuLabel => 'Statistiques de requêtes lentes';

  @override
  String get slowQueryDialogTitle => 'Statistiques de requêtes lentes';

  @override
  String slowQueryScopeBanner(int thresholdMs) {
    return 'Les requêtes exécutées via dbmaster/server plus lentes que $thresholdMs ms sont enregistrées ; lorsque la collecte native du slow log est activée sur l\'instance, les requêtes lentes de la base elle-même sont incluses (distinguées par source).';
  }

  @override
  String get slowQueryWindow1h => 'Dernière heure';

  @override
  String get slowQueryWindow24h => 'Dernières 24 h';

  @override
  String get slowQueryWindow7d => 'Derniers 7 jours';

  @override
  String get slowQuerySortTotalMs => 'Durée totale';

  @override
  String get slowQuerySortCount => 'Nombre';

  @override
  String get slowQuerySortAvgMs => 'Durée moy.';

  @override
  String get slowQuerySortMaxMs => 'Durée max';

  @override
  String get slowQueryAllConnections => 'Toutes les connexions';

  @override
  String slowQueryDigestStats(int count, String total, String avg, String max) {
    return '$count appels · total $total · moy. $avg · max $max';
  }

  @override
  String slowQueryLastSeen(String time) {
    return 'dernière $time';
  }

  @override
  String get slowQueryEmptyTitle => 'Aucune requête lente';

  @override
  String get slowQueryEmptyBody =>
      'Rien au-delà du seuil dans cette fenêtre. Exécutez quelque chose de lent via dbmaster puis revenez.';

  @override
  String get slowQueryLoadFailed => 'Échec du chargement des statistiques.';

  @override
  String get slowQueryRetry => 'Réessayer';

  @override
  String slowQueryLoadMore(int shown, int total) {
    return 'Afficher plus ($shown sur $total)';
  }

  @override
  String get slowQueryStatusOk => 'ok';

  @override
  String get slowQueryStatusError => 'erreur';

  @override
  String get slowQueryStatusCancelled => 'annulée';

  @override
  String get slowQueryDatabaseLabel => 'Base de données';

  @override
  String get slowQueryNoPlaintext =>
      'Le SQL en clair est désactivé sur cette instance (digest uniquement).';

  @override
  String get slowQueryCopySql => 'Copier SQL';

  @override
  String get slowQueryCopied => 'Copié';

  @override
  String get reportsMenuLabel => 'Rapports';

  @override
  String get reportsDialogTitle => 'Rapports';

  @override
  String get reportsGenerateButton => 'Générer le rapport hebdo';

  @override
  String get reportsGeneratedToast => 'Rapport hebdomadaire généré.';

  @override
  String get reportsExistingToast => 'Le rapport de cette semaine existe déjà.';

  @override
  String get reportsEmptyTitle => 'Aucun rapport';

  @override
  String get reportsEmptyBody =>
      'Générez le rapport hebdo des requêtes lentes, ou attendez la cadence hebdomadaire.';

  @override
  String get reportsLoadFailed => 'Échec du chargement des rapports.';

  @override
  String get reportsRetry => 'Réessayer';

  @override
  String reportsLoadMore(int shown, int total) {
    return 'Afficher plus ($shown sur $total)';
  }

  @override
  String get reportsWindowLabel => 'Période';

  @override
  String get reportsTruncatedHint =>
      'Période incomplète : les échantillons plus anciens ont déjà été purgés par la rétention.';

  @override
  String get reportsSamplesLabel => 'Échantillons';

  @override
  String get reportsDistinctLabel => 'Requêtes distinctes';

  @override
  String get reportsTotalTimeLabel => 'Durée totale';

  @override
  String get reportsErrorsLabel => 'Erreurs';

  @override
  String get reportsWowLabel => 'vs semaine dern.';

  @override
  String get reportsTopSection => 'Requêtes les plus lentes';

  @override
  String get reportsByDaySection => 'Par jour';

  @override
  String get reportsByConnectionSection => 'Par connexion';

  @override
  String get reportsUnknownType => 'Type de rapport inconnu — contenu brut :';

  @override
  String get reportsAnalyzeWithAi => 'Analyser avec l\'IA';
}
