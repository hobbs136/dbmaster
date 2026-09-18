// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get filterBarApply => 'Применить';

  @override
  String get filterBarAddCondition => 'Добавить условие';

  @override
  String get filterBarAnd => 'И';

  @override
  String get filterBarOr => 'ИЛИ';

  @override
  String get filterBarNoColumns => 'Нет столбцов';

  @override
  String get filterBarLoading => 'Загрузка…';

  @override
  String get mongoAutocompleteTitle => 'Автодополнение Mongo';

  @override
  String get appTitle => 'DbMaster';

  @override
  String get settingsTitle => 'Настройки';

  @override
  String get settingsLanguage => 'Язык';

  @override
  String get settingsTheme => 'Тема';

  @override
  String get settingsGeneral => 'Общие';

  @override
  String get settingsConnection => 'Подключение';

  @override
  String get settingsEditor => 'Редактор';

  @override
  String get settingsAbout => 'О программе';

  @override
  String get connectionNewConnection => 'Новое подключение';

  @override
  String get connectionEditConnection => 'Редактировать подключение';

  @override
  String get connectionManageConnection => 'Manage Connection';

  @override
  String get connectionDeleteConnection => 'Удалить подключение';

  @override
  String get connectionConnect => 'Подключиться';

  @override
  String get connectionCreateDatabase => 'Создать базу данных';

  @override
  String get connectionEnableReadOnly => 'Включить только чтение';

  @override
  String get connectionDisableReadOnly => 'Отключить только чтение';

  @override
  String connectionMoveToGroup(String groupName) {
    return 'Переместить в $groupName';
  }

  @override
  String get connectionRemoveFromGroup => 'Удалить из группы';

  @override
  String get connectionCollapseAll => 'Свернуть все';

  @override
  String get connectionDisconnect => 'Отключиться';

  @override
  String get connectionTestConnection => 'Проверить подключение';

  @override
  String get connectionConnectionName => 'Имя подключения';

  @override
  String get connectionHost => 'Хост';

  @override
  String get connectionPort => 'Порт';

  @override
  String get connectionUsername => 'Имя пользователя';

  @override
  String get connectionPassword => 'Пароль';

  @override
  String get connectionDatabase => 'База данных';

  @override
  String get connectionEnvironment => 'Окружение';

  @override
  String get connectionEnvironmentNone => 'Не указано';

  @override
  String get commonSave => 'Сохранить';

  @override
  String get commonCancel => 'Отмена';

  @override
  String get commonDelete => 'Удалить';

  @override
  String get commonEdit => 'Редактировать';

  @override
  String get commonAdd => 'Добавить';

  @override
  String get commonClose => 'Закрыть';

  @override
  String get commonDone => 'Done';

  @override
  String get commonSelect => 'Select';

  @override
  String get commonConfirm => 'Подтвердить';

  @override
  String get commonSearch => 'Поиск';

  @override
  String get commonRefresh => 'Обновить';

  @override
  String get commonLoading => 'Загрузка...';

  @override
  String get commonNoData => 'Нет данных';

  @override
  String get commonSuccess => 'Успешно';

  @override
  String get commonError => 'Ошибка';

  @override
  String get commonWarning => 'Предупреждение';

  @override
  String get tableNewTable => 'Новая таблица';

  @override
  String get tableEditTable => 'Редактировать таблицу';

  @override
  String get tableDeleteTable => 'Удалить таблицу';

  @override
  String get tableTableName => 'Имя таблицы';

  @override
  String get tableColumns => 'Столбцы';

  @override
  String get tableIndexes => 'Индексы';

  @override
  String get tablePrimaryKey => 'Первичный ключ';

  @override
  String get tableForeignKey => 'Внешний ключ';

  @override
  String get tableRenameTable => 'Переименовать таблицу';

  @override
  String get tableNewTableName => 'Новое имя таблицы';

  @override
  String get queryExecute => 'Выполнить';

  @override
  String get queryExecuteSelected => 'Выполнить выбранное';

  @override
  String get queryFormat => 'Форматировать';

  @override
  String get queryClear => 'Очистить';

  @override
  String get queryHistory => 'История';

  @override
  String get queryResults => 'Результаты';

  @override
  String get sidebarConnections => 'Подключения';

  @override
  String get sidebarDatabases => 'Базы данных';

  @override
  String get sidebarTables => 'Таблицы';

  @override
  String get sidebarKeys => 'Ключи';

  @override
  String get sidebarCollections => 'Коллекции';

  @override
  String get sidebarSuperTables => 'Супертаблицы';

  @override
  String get sidebarViews => 'Представления';

  @override
  String get sidebarSavedQueries => 'Сохраненные запросы';

  @override
  String get sidebarProcedures => 'Хранимые процедуры';

  @override
  String get sidebarTriggers => 'Триггеры';

  @override
  String get sidebarFunctions => 'Функции';

  @override
  String get sidebarServer => 'Сервер';

  @override
  String get sidebarProcessList => 'Список процессов';

  @override
  String get sidebarServerStatus => 'Состояние сервера';

  @override
  String get sidebarNoUsers => 'Нет пользователей';

  @override
  String get sidebarNoActiveProcesses => 'Нет активных процессов';

  @override
  String sidebarTdColsTags(int cols, int tags) {
    return '$cols столб., $tags тегов';
  }

  @override
  String sidebarTdColumnsCount(int count) {
    return 'Столбцы ($count)';
  }

  @override
  String sidebarTdTagsCount(int count) {
    return 'Теги ($count)';
  }

  @override
  String get sidebarTdDeleteTitle => 'Удалить SuperTable';

  @override
  String sidebarTdDeleteConfirm(String name) {
    return 'Вы действительно хотите удалить SuperTable «$name»?\n\nЭто также удалит все её SubTable!';
  }

  @override
  String get sidebarDeleteGroup => 'Удалить группу';

  @override
  String get sidebarDeleteGroupPrompt => 'Выберите группу для удаления:';

  @override
  String get sidebarConnectionSwitch => 'Переключить подключение';

  @override
  String get sidebarSelectConnectionHint =>
      'Выберите подключение в селекторе выше, чтобы начать';

  @override
  String get sidebarConnectionNone => 'Нет подключений';

  @override
  String get sidebarManageConnections => 'Управление подключениями…';

  @override
  String get sidebarExtensions => 'Extensions';

  @override
  String get noExtensionsInstalled => 'No extensions installed';

  @override
  String get sidebarSchemas => 'Схемы';

  @override
  String get sidebarMaterializedViews => 'Материализованные представления';

  @override
  String get sidebarSequences => 'Последовательности';

  @override
  String get settingsGeneralSettings => 'Общие настройки';

  @override
  String get settingsAppearanceSettings => 'Внешний вид';

  @override
  String get settingsEditorSettings => 'Настройки редактора';

  @override
  String get settingsEnableAutocomplete => 'Включить автозаполнение';

  @override
  String get settingsAutocompleteDescription =>
      'Автоматически предлагать SQL ключевые слова и имена таблиц';

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
  String get settingsAiSettings => 'Настройки ИИ';

  @override
  String get settingsAutoExecuteSql => 'Автоматическое выполнение SQL';

  @override
  String get settingsAutoExecuteSqlDescription =>
      'Автоматически выполнять SQL при открытии вкладки';

  @override
  String get settingsThemeSettings => 'Тема';

  @override
  String get settingsDarkMode => 'Тёмный';

  @override
  String get settingsLightMode => 'Светлый';

  @override
  String get shortcutCategoryFile => 'Файл';

  @override
  String get shortcutCategoryEdit => 'Редактирование';

  @override
  String get shortcutCategoryView => 'Вид';

  @override
  String get shortcutCategoryAi => 'ИИ';

  @override
  String get shortcutCategoryTab => 'Вкладки';

  @override
  String get shortcutNewConnection => 'Новое подключение';

  @override
  String get shortcutNewTab => 'Новая вкладка';

  @override
  String get shortcutCloseTab => 'Закрыть вкладку';

  @override
  String get shortcutSaveQuery => 'Сохранить запрос';

  @override
  String get shortcutExportData => 'Экспорт данных';

  @override
  String get shortcutExecuteQuery => 'Выполнить запрос';

  @override
  String get shortcutExecuteQueryNewTab => 'Выполнить в новой вкладке';

  @override
  String get shortcutFormatSql => 'Форматировать SQL';

  @override
  String get shortcutFind => 'Найти';

  @override
  String get shortcutReplace => 'Заменить';

  @override
  String get shortcutAutocomplete => 'Автозаполнение';

  @override
  String get shortcutUndo => 'Отменить';

  @override
  String get shortcutRedo => 'Повторить';

  @override
  String get shortcutToggleSidebar => 'Переключить боковую панель';

  @override
  String get shortcutToggleAiPanel => 'Переключить панель ИИ';

  @override
  String get shortcutCommandPalette => 'Палитра команд';

  @override
  String get shortcutShortcutHelp => 'Справка по ярлыкам';

  @override
  String get shortcutGenerateSql => 'Генерировать SQL';

  @override
  String get shortcutOptimizeSql => 'Оптимизировать SQL';

  @override
  String get shortcutExplainSql => 'Объяснить SQL';

  @override
  String get shortcutNextTab => 'Следующая вкладка';

  @override
  String get shortcutPreviousTab => 'Предыдущая вкладка';

  @override
  String get shortcutSwitchToTab => 'Переключиться на вкладку';

  @override
  String get shortcutToggleAiFullscreen => 'Панель ИИ на весь экран';

  @override
  String get shortcutAuditLog => 'Журнал аудита запросов';

  @override
  String get shortcutIncreaseOpacity => 'Увеличить непрозрачность наложения';

  @override
  String get shortcutDecreaseOpacity => 'Уменьшить непрозрачность наложения';

  @override
  String get tableCreateNewTable => 'Создать новую таблицу';

  @override
  String get toolbarBackup => 'Резервное копирование';

  @override
  String get toolbarImport => 'Импорт';

  @override
  String get toolbarExport => 'Экспорт';

  @override
  String get sidebarExpand => 'Развернуть боковую панель';

  @override
  String get sidebarSettings => 'Настройки';

  @override
  String get sidebarSearchHint => 'Поиск подключений, таблиц, представлений...';

  @override
  String sidebarConnectionActive(Object count) {
    return '$count активных подключений';
  }

  @override
  String get sidebarNoConnections => 'Нет сохраненных подключений';

  @override
  String get sidebarClickToCreateConnection =>
      'Нажмите кнопку ниже, чтобы создать новое подключение';

  @override
  String get sidebarCreateConnection => 'Создать подключение';

  @override
  String get resultsExport => 'Экспорт';

  @override
  String get resultsSave => 'Сохранить';

  @override
  String get resultsDiscard => 'Отменить';

  @override
  String get resultsNoDataToExport => 'Нет данных для экспорта';

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
  String get resultsConfirmDiscardChanges => 'Подтвердить отмену изменений';

  @override
  String resultsDiscardChangesMessage(Object count) {
    return 'Вы уверены, что хотите отменить $count изменений? Это действие нельзя отменить.';
  }

  @override
  String get resultsContinueEditing => 'Продолжить редактирование';

  @override
  String get resultsDiscardChanges => 'Отменить изменения';

  @override
  String get resultsConfirmExecuteSQL => 'Подтвердить выполнение SQL';

  @override
  String get resultsBarChart => 'Столбчатая диаграмма';

  @override
  String get resultsLineChart => 'Линейная диаграмма';

  @override
  String get resultsPieChart => 'Круговая диаграмма';

  @override
  String get resultsSelectAxisFields =>
      'Пожалуйста, выберите поля для осей X и Y';

  @override
  String get statusNotConnected => 'Не подключено';

  @override
  String get statusConnected => 'Подключено';

  @override
  String statusTables(Object count) {
    return '$count таблиц';
  }

  @override
  String get statusNone => 'Нет';

  @override
  String statusVersion(Object version) {
    return 'v$version';
  }

  @override
  String get backupManagement => 'Управление резервными копиями';

  @override
  String get backupList => 'Список резервных копий';

  @override
  String get createBackup => 'Создать резервную копию';

  @override
  String get noBackupFiles => 'Нет файлов резервных копий';

  @override
  String get clickCreateBackupTab =>
      'Нажмите вкладку \'Создать резервную копию\', чтобы начать резервное копирование';

  @override
  String get importBackup => 'Импортировать резервную копию';

  @override
  String get previewContent => 'Просмотр содержимого';

  @override
  String get exportFile => 'Экспорт файла';

  @override
  String get restoreBackup => 'Восстановить резервную копию';

  @override
  String get selectBackupToView =>
      'Выберите резервную копию для просмотра деталей';

  @override
  String get database => 'База данных';

  @override
  String get backupType => 'Тип';

  @override
  String get backupSize => 'Размер';

  @override
  String get createdAt => 'Создано';

  @override
  String get tableCount => 'Количество таблиц';

  @override
  String get description => 'Описание';

  @override
  String get preview => 'Просмотр';

  @override
  String get export => 'Экспорт';

  @override
  String get restore => 'Восстановить';

  @override
  String get confirmRestore => 'Подтвердить восстановление';

  @override
  String confirmRestoreMessage(Object name) {
    return 'Вы уверены, что хотите восстановить резервную копию \"$name\"?\n\nЭто выполнит все SQL-инструкции из файла резервной копии, что может перезаписать существующие данные.';
  }

  @override
  String get confirmDelete => 'Подтвердить удаление';

  @override
  String confirmDeleteMessage(Object name) {
    return 'Вы уверены, что хотите удалить резервную копию \"$name\"?\n\nЭто действие нельзя отменить.';
  }

  @override
  String get backupFormat => 'Формат резервной копии';

  @override
  String get backupContent => 'Содержимое резервной копии';

  @override
  String get selectTablesHint =>
      'Выберите таблицы (оставьте пустым для резервного копирования всех)';

  @override
  String get advancedOptions => 'Расширенные параметры';

  @override
  String get includeStructure => 'Включить структуру таблиц';

  @override
  String get includeStructureDesc => 'Инструкции CREATE TABLE';

  @override
  String get includeData => 'Включить данные';

  @override
  String get includeDataDesc => 'Инструкции INSERT или строки данных';

  @override
  String get noTablesAvailable => 'Нет доступных таблиц';

  @override
  String get selectAll => 'Выбрать все';

  @override
  String get deselectAll => 'Отменить выбор всех';

  @override
  String tablesSelected(Object count) {
    return 'Выбрано $count таблиц';
  }

  @override
  String get addDropTable => 'Добавить DROP TABLE';

  @override
  String get useExtendedInsert => 'Использовать расширенный INSERT';

  @override
  String get useExtendedInsertDesc =>
      'Объединить несколько строк значений в один INSERT';

  @override
  String get rowLimitPerTable => 'Ограничение строк на таблицу (необязательно)';

  @override
  String get leaveEmptyForNoLimit =>
      'Оставьте пустым для отсутствия ограничений';

  @override
  String get whereCondition => 'Условие WHERE (необязательно)';

  @override
  String get whereConditionExample => 'Например: id > 100';

  @override
  String get enterBackupDescription =>
      'Введите описание резервной копии (необязательно)';

  @override
  String get startBackup => 'Начать резервное копирование';

  @override
  String get backupProgress => 'Прогресс резервного копирования';

  @override
  String get waitingToStartBackup =>
      'Ожидание начала резервного копирования...';

  @override
  String get currentTable => 'Текущая таблица';

  @override
  String get progressPercent => 'Прогресс';

  @override
  String get backupComplete => 'Резервное копирование завершено!';

  @override
  String get backupFailed => 'Ошибка резервного копирования';

  @override
  String get loadBackupListFailed =>
      'Не удалось загрузить список резервных копий';

  @override
  String get retry => 'Повторить попытку';

  @override
  String get previewFailed => 'Ошибка предпросмотра';

  @override
  String get exportedTo => 'Экспортировано в';

  @override
  String get backupRestoreSuccess =>
      'Восстановление из резервной копии успешно выполнено';

  @override
  String get restoreFailed => 'Ошибка восстановления';

  @override
  String get backupDeleted => 'Резервная копия удалена';

  @override
  String deleteFailed(Object error) {
    return 'Ошибка удаления: $error';
  }

  @override
  String get selectBackupFile => 'Выберите файл резервной копии';

  @override
  String get backupImportSuccess => 'Файл резервной копии успешно импортирован';

  @override
  String importFailed(String error) {
    return 'Ошибка импорта: $error';
  }

  @override
  String get selectAtLeastOneOption =>
      'Пожалуйста, выберите хотя бы резервное копирование структуры или данных';

  @override
  String get backupFailedError => 'Ошибка резервного копирования';

  @override
  String get aiAssistant => 'ИИ-помощник';

  @override
  String get aiAnalyze => 'ИИ-анализ';

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
  String get apiSettings => 'Настройки API';

  @override
  String get clearChat => 'Очистить чат';

  @override
  String get model => 'Модель';

  @override
  String get enterModelName => 'Введите название модели';

  @override
  String get autoExecuteSql => 'Автоматическое выполнение SQL';

  @override
  String get autoExecuteSqlDesc =>
      'При включении SQL-запросы, сгенерированные ИИ, будут автоматически выполняться';

  @override
  String get aiDatabaseAssistant => 'ИИ-помощник по базам данных';

  @override
  String get aiAssistantDesc =>
      'Поддержка нескольких поставщиков моделей\nПоможет писать SQL, оптимизировать запросы, объяснять структуру базы данных';

  @override
  String get enterYourQuestion => 'Введите ваш вопрос...';

  @override
  String configureApiKeyFirst(Object provider) {
    return 'Пожалуйста, сначала настройте API-ключ $provider в настройках, чтобы включить функцию ИИ-чата.\n\nНажмите на значок настроек в правом верхнем углу для настройки.';
  }

  @override
  String get generationFailed => 'Ошибка генерации';

  @override
  String get stepAnalyzeNeeds =>
      'Шаг 1: Анализ требований пользователя, определение необходимых таблиц...';

  @override
  String get stepGetTableSchema =>
      'Шаг 2: Получение подробных инструкций CREATE TABLE для таблиц...';

  @override
  String get stepGenerateSql => 'Шаг 3: Генерация SQL-инструкций...';

  @override
  String get analysisResultTables =>
      'Результат анализа: Таблицы, которые необходимо запросить';

  @override
  String get tableSchemaInfo => 'Информация о структуре таблиц';

  @override
  String get operationCancelled => 'Операция отменена';

  @override
  String get executingSql => 'Выполнение SQL...';

  @override
  String executeSuccessRows(Object count) {
    return 'Выполнение успешно, возвращено $count строк данных';
  }

  @override
  String get executeFailedError => 'Ошибка выполнения';

  @override
  String get confirmDangerousOperation =>
      'Подтвердить выполнение опасной операции?';

  @override
  String get confirmExecuteSql => 'Подтвердить выполнение SQL';

  @override
  String get dangerousOperationWarning =>
      'Эта операция может изменить или удалить данные, пожалуйста, действуйте с осторожностью!';

  @override
  String get sqlCopied => 'SQL скопирован';

  @override
  String get sqlGenerationComplete => 'Генерация SQL завершена';

  @override
  String get dangerousOperation => 'Опасная операция';

  @override
  String get dangerousOperationDesc =>
      'Это опасная операция, пожалуйста, действуйте с осторожностью';

  @override
  String get taskCompleteDesc =>
      'Задача завершена, вы можете выполнить или скопировать SQL';

  @override
  String get generatedSql => 'Сгенерированный SQL';

  @override
  String get dangerous => 'Опасно';

  @override
  String get confirmExecute => 'Подтвердить выполнение';

  @override
  String get requestTimeout => 'Таймаут запроса';

  @override
  String get seconds => 'секунд';

  @override
  String get apiSettingsSaved => 'Настройки API сохранены';

  @override
  String get dataImport => 'Импорт данных';

  @override
  String get selectFile => 'Выбрать файл';

  @override
  String get noFileSelected => 'Файл не выбран';

  @override
  String get importConfig => 'Конфигурация импорта';

  @override
  String get targetTableName => 'Имя целевой таблицы';

  @override
  String get enterTableName => 'Введите имя таблицы';

  @override
  String get includeHeader => 'Включить заголовок';

  @override
  String get delimiter => 'Разделитель';

  @override
  String get overwriteTable => 'Перезаписать таблицу';

  @override
  String get deleteExistingTable => '(Удалить существующую таблицу)';

  @override
  String get batchSize => 'Размер пакета';

  @override
  String dataPreviewRows(Object count) {
    return 'Предпросмотр данных ($count строк)';
  }

  @override
  String get pleaseSelectFile =>
      'Пожалуйста, выберите файл для предпросмотра данных';

  @override
  String get importProgress => 'Прогресс импорта';

  @override
  String get importPreparing => 'Подготовка к импорту...';

  @override
  String get totalRecords => 'Всего записей';

  @override
  String get importedRecords => 'Импортировано';

  @override
  String get failedRecords => 'Ошибок';

  @override
  String get readyToImport => 'Готов к импорту';

  @override
  String get importingData => 'Импорт данных...';

  @override
  String get importComplete => 'Импорт завершен!';

  @override
  String get parseFileFailed => 'Ошибка разбора файла';

  @override
  String get noDataToImport => 'Нет данных для импорта';

  @override
  String get selectDatabaseFirst => 'Пожалуйста, сначала выберите базу данных';

  @override
  String get importFailedError => 'Ошибка импорта';

  @override
  String get startImport => 'Начать импорт';

  @override
  String get importing => 'Импортирование...';

  @override
  String get optimizeSql => 'Оптимизировать SQL';

  @override
  String get explainQuery => 'Объяснить запрос';

  @override
  String get generateInsert => 'Сгенерировать INSERT';

  @override
  String get generateUpdate => 'Сгенерировать UPDATE';

  @override
  String get generateDelete => 'Сгенерировать DELETE';

  @override
  String get createTableStatement => 'Инструкция CREATE TABLE';

  @override
  String get securityCheck => 'Проверка безопасности';

  @override
  String get indexSuggestion => 'Предложение индекса';

  @override
  String get executionPlan => 'План выполнения';

  @override
  String get pleaseEnterSql => 'Пожалуйста, сначала введите SQL-инструкцию';

  @override
  String get pleaseConnectDatabase =>
      'Пожалуйста, сначала подключитесь к базе данных';

  @override
  String get analysisFailed => 'Ошибка анализа';

  @override
  String get loadHistoryFailed => 'Ошибка загрузки истории';

  @override
  String get noQueryHistory =>
      'Нет записей в истории запросов\n\nПосле выполнения SQL-запросов история будет сохранена здесь.';

  @override
  String queryHistoryRecords(Object count) {
    return 'Записи истории запросов (последние $count)';
  }

  @override
  String get databaseType => 'Тип базы данных';

  @override
  String get server => 'Сервер';

  @override
  String get currentDatabase => 'Текущая база данных';

  @override
  String get notConnected => 'Не подключено';

  @override
  String get notSelected => 'Не выбрано';

  @override
  String get tableName => 'Имя таблицы';

  @override
  String get tableStructureInfo => 'Информация о структуре таблицы';

  @override
  String get createStatement => 'Инструкция CREATE';

  @override
  String andMoreTables(Object count) {
    return '... и еще $count таблиц';
  }

  @override
  String get primaryKey => 'Первичный ключ';

  @override
  String get executionTime => 'Время выполнения';

  @override
  String get status => 'Статус';

  @override
  String get commonFailed => 'Не удалось';

  @override
  String get format => 'Формат';

  @override
  String get connectionDefaultDatabase => 'База данных по умолчанию';

  @override
  String get connectionSavePassword => 'Сохранить пароль';

  @override
  String get connectionAdvancedOptions => 'Расширенные параметры';

  @override
  String get connectionTimeout => 'Таймаут (сек)';

  @override
  String get connectionUseSSL => 'Использовать SSL/TLS';

  @override
  String get connectionEnableSecureConnection =>
      'Включить безопасное подключение';

  @override
  String get connectionUseTls => 'Использовать TLS/SSL';

  @override
  String get connectionUseTlsDesc =>
      'Шифрованное соединение по TLS (устанавливается на стороне сервера)';

  @override
  String get connectionTlsInsecure =>
      'Пропустить проверку сертификата (небезопасно)';

  @override
  String get connectionTlsInsecureDesc =>
      'Не проверять сертификат сервера — только для доверенных/тестовых окружений';

  @override
  String get connectionSshSubtitleGateway =>
      'SSH-туннель устанавливается на стороне сервера dbmaster (конфигурация передаётся вместе с подключением)';

  @override
  String get connectionAutoReconnect => 'Автоматическое переподключение';

  @override
  String get connectionAutoReconnectDesc =>
      'Автоматически пытаться переподключиться при разрыве соединения';

  @override
  String get connectionCharset => 'Кодировка';

  @override
  String get connectionTimezone => 'Часовой пояс';

  @override
  String get connectionTestSuccess => 'Подключение успешно!';

  @override
  String connectionTestFailed(String error) {
    return 'Ошибка подключения';
  }

  @override
  String get connectionDatabaseType => 'Тип базы данных';

  @override
  String get connectionManager => 'Управление подключениями';

  @override
  String get connectionSavedConnections => 'Сохраненные подключения';

  @override
  String get connectionNoSavedConnections => 'Нет сохраненных подключений';

  @override
  String get connectionCurrent => 'Текущее';

  @override
  String get connectionConnected => 'Подключено';

  @override
  String get connectionSwitchToConnection => 'Переключиться на это подключение';

  @override
  String get connectionCloneConnection => 'Клонировать подключение';

  @override
  String get connectionCloned => 'Подключение клонировано';

  @override
  String get connectionDeleteConnectionTitle => 'Удалить подключение';

  @override
  String get connectionDeleteConnectionConfirm =>
      'Вы уверены, что хотите удалить подключение';

  @override
  String get connectionDisconnectAll => 'Отключить все';

  @override
  String get searchDialogTitle => 'Поиск';

  @override
  String get searchHint =>
      'Поиск таблиц, представлений, хранимых процедур, столбцов...';

  @override
  String get searchNoResults => 'Объекты не найдены';

  @override
  String get searchTryDifferentKeywords => 'Попробуйте другие ключевые слова';

  @override
  String get searchNavigate => 'Навигация';

  @override
  String get searchSelect => 'Выбрать';

  @override
  String get searchClose => 'Закрыть';

  @override
  String searchResultsCount(Object count) {
    return '$count результатов';
  }

  @override
  String get searchTypeConnection => 'Подключение';

  @override
  String get searchTypeDatabase => 'База данных';

  @override
  String get searchTypeTable => 'Таблица';

  @override
  String get searchTypeView => 'Представление';

  @override
  String get searchTypeProcedure => 'Хранимая процедура';

  @override
  String get searchTypeColumn => 'Столбец';

  @override
  String get savedQueriesTitle => 'Сохраненные запросы';

  @override
  String get savedQueriesNoQueries => 'Нет сохраненных запросов';

  @override
  String get savedQueriesDeleteTitle => 'Удалить запрос';

  @override
  String get savedQueriesDeleteConfirm =>
      'Вы уверены, что хотите удалить этот запрос?';

  @override
  String get savedQueriesOpen => 'Открыть';

  @override
  String get viewJson => 'Просмотр JSON';

  @override
  String get extractFieldAsColumn => 'Извлечь поле как столбец';

  @override
  String get erDiagramTitle => 'ER-диаграмма';

  @override
  String get erDiagramSearchTables => 'Поиск таблиц...';

  @override
  String get erDiagramHierarchicalLayout => 'Иерархическое расположение';

  @override
  String get erDiagramForceDirectedLayout => 'Расположение силами';

  @override
  String get erDiagramCircleLayout => 'Круговое расположение';

  @override
  String get erDiagramResetLayout => 'Сбросить расположение';

  @override
  String get erDiagramZoomIn => 'Увеличить';

  @override
  String get erDiagramZoomOut => 'Уменьшить';

  @override
  String get erDiagramFitToScreen => 'По размеру экрана';

  @override
  String get erDiagramRelations => 'Отношения';

  @override
  String get erDiagramZoom => 'Масштаб';

  @override
  String get erDiagramShowIsolated => 'Показать изолированные';

  @override
  String get erDiagramExportAsPNG => 'Экспортировать как PNG';

  @override
  String get erDiagramExportAsJPG => 'Экспортировать как JPG';

  @override
  String get erDiagramLoading => 'Загрузка ER-диаграммы...';

  @override
  String get erDiagramErrorLoading => 'Ошибка загрузки ER-диаграммы';

  @override
  String get erDiagramNoData => 'Нет данных для диаграммы';

  @override
  String get erDiagramRetry => 'Повторить попытку';

  @override
  String get erDiagramSelectConnection => 'Выбрать подключение';

  @override
  String get erDiagramSelectDatabase => 'Выбрать базу данных';

  @override
  String get performanceAnalyzerTitle =>
      'Инструмент анализа производительности';

  @override
  String get performanceAnalyzerSearch => 'Поиск...';

  @override
  String get performanceAnalyzerRefresh => 'Обновить данные';

  @override
  String get performanceAnalyzerGenerateReport => 'Сгенерировать отчет';

  @override
  String get performanceAnalyzerExport => 'Экспортировать';

  @override
  String get performanceAnalyzerClose => 'Закрыть';

  @override
  String get performanceAnalyzerNotConnected => 'Не подключено к базе данных';

  @override
  String get performanceAnalyzerNotConnectedDesc =>
      'Пожалуйста, сначала подключитесь к базе данных, чтобы использовать функцию анализа производительности';

  @override
  String get performanceAnalyzerConfirm => 'Подтвердить';

  @override
  String get performanceAnalyzerSlowQueryAnalysis =>
      'Анализ медленных запросов';

  @override
  String get performanceAnalyzerIndexAnalysis => 'Анализ индексов';

  @override
  String get performanceAnalyzerTableStatistics => 'Статистика таблиц';

  @override
  String get performanceAnalyzerPerformanceReport =>
      'Отчет о производительности';

  @override
  String get performanceAnalyzerLoading =>
      'Анализ производительности базы данных...';

  @override
  String get performanceAnalyzerLoadFailed => 'Ошибка загрузки';

  @override
  String get performanceAnalyzerRetry => 'Повторить попытку';

  @override
  String get performanceAnalyzerTimeThreshold => 'Порог времени:';

  @override
  String get performanceAnalyzerNoSlowQueries => 'Медленные запросы не найдены';

  @override
  String get performanceAnalyzerSelectQuery =>
      'Выберите запрос для просмотра деталей';

  @override
  String get performanceAnalyzerQueryInfo => 'Информация о запросе';

  @override
  String get performanceAnalyzerExecutionTime => 'Время выполнения';

  @override
  String get performanceAnalyzerDatabase => 'База данных';

  @override
  String get performanceAnalyzerRowsScaned => 'Сканировано строк';

  @override
  String get performanceAnalyzerRowsReturned => 'Возвращено строк';

  @override
  String get performanceAnalyzerTimestamp => 'Время выполнения';

  @override
  String get performanceAnalyzerSqlStatement => 'SQL-инструкция';

  @override
  String get performanceAnalyzerExecutionPlan => 'План выполнения';

  @override
  String get performanceAnalyzerOptimizationSuggestions =>
      'Предложения по оптимизации';

  @override
  String get performanceAnalyzerFullTableScan =>
      'Обнаружено полное сканирование таблицы';

  @override
  String get performanceAnalyzerFullTableScanDesc =>
      'Запрос использует полное сканирование (type=ALL), рекомендуется добавить индекс для столбцов в WHERE';

  @override
  String get performanceAnalyzerFileSort => 'Сортировка файлов';

  @override
  String get performanceAnalyzerFileSortDesc =>
      'Запрос использует сортировку файлов (Using filesort), рекомендуется добавить индекс для столбцов в ORDER BY';

  @override
  String get performanceAnalyzerTempTable => 'Использование временных таблиц';

  @override
  String get performanceAnalyzerTempTableDesc =>
      'Запрос использует временные таблицы (Using temporary), рассмотрите возможность оптимизации запросов с GROUP BY или DISTINCT';

  @override
  String get performanceAnalyzerLowScanEfficiency =>
      'Низкая эффективность сканирования';

  @override
  String get performanceAnalyzerNoIssues => 'Очевидных проблем не обнаружено';

  @override
  String get performanceAnalyzerNoIssuesDesc =>
      'План выполнения запроса выглядит нормально';

  @override
  String get performanceAnalyzerIndexTypeDistribution =>
      'Распределение типов индексов';

  @override
  String get performanceAnalyzerNoData => 'Нет данных';

  @override
  String get performanceAnalyzerTotalIndexes => 'Всего индексов';

  @override
  String get performanceAnalyzerUsedIndexes => 'Использовано';

  @override
  String get performanceAnalyzerUnusedIndexes => 'Не использовано';

  @override
  String get performanceAnalyzerIndexes => 'индексов';

  @override
  String get performanceAnalyzerColumns => 'Столбцы:';

  @override
  String get performanceAnalyzerCardinality => 'Кардинальность:';

  @override
  String get performanceAnalyzerTotalTables => 'Всего таблиц';

  @override
  String get performanceAnalyzerTotalRows => 'Всего строк';

  @override
  String get performanceAnalyzerDataSize => 'Размер данных';

  @override
  String get performanceAnalyzerIndexSize => 'Размер индексов';

  @override
  String get performanceAnalyzerTotalSize => 'Общий размер';

  @override
  String get performanceAnalyzerTableName => 'Имя таблицы';

  @override
  String get performanceAnalyzerEngine => 'Движок';

  @override
  String get performanceAnalyzerRowCount => 'Количество строк';

  @override
  String get performanceAnalyzerPercentage => 'Процент';

  @override
  String get performanceAnalyzerTableSizeDistribution =>
      'Распределение размеров таблиц (Топ 10)';

  @override
  String get performanceAnalyzerDatabasePerformanceReport =>
      'Отчет о производительности базы данных';

  @override
  String get performanceAnalyzerGeneratedAt => 'Сгенерировано:';

  @override
  String get performanceAnalyzerTableCount => 'Количество таблиц';

  @override
  String get performanceAnalyzerSlowQueries => 'Медленные запросы';

  @override
  String get performanceAnalyzerSuggestions => 'Предложения';

  @override
  String get performanceAnalyzerImpact => 'Влияние:';

  @override
  String get performanceAnalyzerImpactHigh => 'Высокое';

  @override
  String get performanceAnalyzerImpactMedium => 'Среднее';

  @override
  String get performanceAnalyzerImpactLow => 'Низкое';

  @override
  String get performanceAnalyzerRecommendation => 'Рекомендуемое действие:';

  @override
  String get performanceAnalyzerSlowQueriesTop => 'Топ медленных запросов';

  @override
  String get performanceAnalyzerLargeTableStatistics =>
      'Статистика больших таблиц';

  @override
  String get performanceAnalyzerClickGenerateReport =>
      'Нажмите кнопку \'Сгенерировать отчет\', чтобы начать анализ';

  @override
  String get sqlHistoryTitle => 'История SQL';

  @override
  String get sqlHistoryNoHistory => 'Нет истории';

  @override
  String get sqlHistoryClose => 'Закрыть';

  @override
  String get sqlHistoryDelete => 'Удалить';

  @override
  String get sqlHistoryConfirmDelete => 'Подтвердить удаление';

  @override
  String get sqlHistoryDeleteConfirm =>
      'Вы уверены, что хотите удалить эту запись истории?';

  @override
  String get sqlHistoryJustNow => 'Только что';

  @override
  String sqlHistoryMinutesAgo(Object count) {
    return '$count минут назад';
  }

  @override
  String sqlHistoryHoursAgo(Object count) {
    return '$count часов назад';
  }

  @override
  String sqlHistoryDaysAgo(Object count) {
    return '$count дней назад';
  }

  @override
  String get aiPanelApiSettings => 'Настройки API';

  @override
  String get aiPanelApiKey => 'API-ключ';

  @override
  String get aiPanelEnterApiKey => 'Введите API-ключ';

  @override
  String get aiPanelApiBaseUrl => 'Базовый URL API (необязательно)';

  @override
  String get aiPanelCustomApiUrl => 'Пользовательский URL API';

  @override
  String get aiPanelRequestTimeout => 'Таймаут запроса:';

  @override
  String get aiPanelSeconds => 'секунд';

  @override
  String get aiPanelSave => 'Сохранить';

  @override
  String get aiPanelApiSettingsSaved => 'Настройки API сохранены';

  @override
  String get aiPanelConfirmDangerousOperation =>
      'Подтвердить выполнение опасной операции?';

  @override
  String get aiPanelConfirmExecuteSql => 'Подтвердить выполнение SQL';

  @override
  String get aiPanelDangerousOperationWarning =>
      'Эта операция может изменить или удалить данные, пожалуйста, действуйте с осторожностью!';

  @override
  String get aiPanelCancel => 'Отмена';

  @override
  String get aiPanelConfirmExecute => 'Подтвердить выполнение';

  @override
  String get aiPanelOperationCancelled => 'Операция отменена';

  @override
  String get aiPanelExecutingSql => 'Выполнение SQL...';

  @override
  String aiPanelExecuteSuccess(Object count) {
    return 'Выполнение успешно, возвращено $count строк';
  }

  @override
  String get aiPanelExecuteFailed => 'Ошибка выполнения';

  @override
  String get aiPanelDataPreview => 'Предпросмотр данных';

  @override
  String aiPanelAndMoreRows(Object count) {
    return 'и еще $count строк';
  }

  @override
  String aiPanelSqlExecutionSuccess(Object count) {
    return 'SQL выполнен успешно, возвращено $count строк';
  }

  @override
  String get aiPanelSqlGenerationComplete => 'Генерация SQL завершена';

  @override
  String get aiPanelSqlGenerationCompleteWarning =>
      'Генерация SQL завершена ⚠️';

  @override
  String get aiPanelTaskCompleteDesc =>
      'Задача завершена, вы можете выполнить или скопировать SQL';

  @override
  String get aiPanelDangerousOperationDesc =>
      'Это опасная операция, пожалуйста, действуйте с осторожностью';

  @override
  String get aiPanelGeneratedSql => 'Сгенерированный SQL';

  @override
  String get aiPanelDangerous => 'Опасно';

  @override
  String get aiPanelContinue => 'Продолжить';

  @override
  String get aiPanelClose => 'Закрыть';

  @override
  String get aiPanelCopy => 'Копировать';

  @override
  String get aiPanelExecute => 'Выполнить';

  @override
  String get aiPanelConfirmExecuteDangerous => 'Подтвердить выполнение';

  @override
  String get quickActionsTitle => 'Быстрые действия';

  @override
  String get quickActionsNewTable => 'Новая таблица';

  @override
  String get quickActionsNewQuery => 'Новый запрос';

  @override
  String get quickActionsAiAssistant => 'ИИ-помощник';

  @override
  String get quickActionsSelectDatabaseFirst =>
      'Пожалуйста, сначала выберите базу данных';

  @override
  String get resultsTabResults => 'Результаты';

  @override
  String get resultsTabMessages => 'Сообщения';

  @override
  String get resultsTabExecutionPlan => 'План выполнения';

  @override
  String get resultsTabExecutionDetails => 'Execution Details';

  @override
  String get resultsSearchBtn => 'Поиск';

  @override
  String get resultsSearchHint => 'Search in results…';

  @override
  String resultsSearchNoMatch(Object query) {
    return 'No rows match \"$query\"';
  }

  @override
  String get resultsClear => 'Очистить';

  @override
  String get resultsSubmit => 'Отправить';

  @override
  String get resultsSearchResults => 'Поиск в результатах';

  @override
  String get resultsViewTable => 'Таблица';

  @override
  String get resultsViewCard => 'Карточка';

  @override
  String get resultsViewChart => 'Диаграмма';

  @override
  String get resultsViewStatistics => 'Статистика';

  @override
  String get paginationShowing => 'Показано';

  @override
  String get paginationRows => 'строк';

  @override
  String get paginationFirstPage => 'Первая страница';

  @override
  String get paginationPreviousPage => 'Предыдущая страница';

  @override
  String get paginationNextPage => 'Следующая страница';

  @override
  String get paginationLastPage => 'Последняя страница';

  @override
  String get editModeTitle => 'Режим редактирования';

  @override
  String get editModeChanges => 'изменений';

  @override
  String get editModeHint =>
      'Двойной клик для редактирования | Enter для подтверждения | Esc для отмены | Tab для переключения';

  @override
  String get resultsNoDataTitle => 'Нет результатов';

  @override
  String get resultsNoDataMessage =>
      'Результаты появятся после выполнения запроса';

  @override
  String get resultsNoDataCardMessage =>
      'Вид карточки появится после выполнения запроса';

  @override
  String get resultsNoDataChartMessage =>
      'Диаграмма появится после выполнения запроса';

  @override
  String get resultsNoDataStatisticsMessage =>
      'Статистика появится после выполнения запроса';

  @override
  String get resultsNoDataExecutionPlanMessage =>
      'Нажмите кнопку \'План выполнения\', чтобы просмотреть план выполнения запроса';

  @override
  String get statisticsTotalRows => 'Всего строк';

  @override
  String get statisticsFieldInfo => 'Информация о полях';

  @override
  String get statisticsNumeric => 'Числовое';

  @override
  String get statisticsText => 'Текст';

  @override
  String get statisticsNumericStats => 'Числовая статистика';

  @override
  String get statisticsCount => 'Количество';

  @override
  String get statisticsSum => 'Сумма';

  @override
  String get statisticsAvg => 'Среднее';

  @override
  String get statisticsMin => 'Минимум';

  @override
  String get statisticsMax => 'Максимум';

  @override
  String get chartXAxis => 'Ось X';

  @override
  String get chartYAxis => 'Ось Y';

  @override
  String get chartType => 'Тип: ';

  @override
  String get chartCannotGenerate =>
      'Невозможно создать диаграмму: Убедитесь, что поле оси Y содержит числовые данные';

  @override
  String messagesQuerySuccess(Object cols, Object rows) {
    return 'Запрос выполнен успешно, возвращено $rows строк, $cols столбцов';
  }

  @override
  String get messagesExecuteToSeeResults =>
      'Информация о результатах появится после выполнения запроса';

  @override
  String sqlPreviewWillExecute(Object count, Object table) {
    return 'Будет выполнено $count SQL-инструкций в таблице `$table`:';
  }

  @override
  String get saveErrorNoTab =>
      'Невозможно сохранить: Текущая вкладка не существует';

  @override
  String get saveErrorCannotExtractTable =>
      'Невозможно сохранить: Невозможно извлечь имя таблицы из запроса';

  @override
  String saveErrorFailed(Object error) {
    return 'Ошибка сохранения: $error';
  }

  @override
  String get exportSelectFormat => 'Выберите формат экспорта';

  @override
  String get toolbarExecute => 'Выполнить';

  @override
  String get toolbarStop => 'Остановить';

  @override
  String get toolbarReadOnlyChip => 'Только чтение';

  @override
  String get toolbarLimitChipTooltip =>
      'Лимит строк для этого подключения (авто LIMIT)';

  @override
  String get toolbarTimeoutChipTooltip =>
      'Тайм-аут запроса для этого подключения';

  @override
  String get toolbarChipFollowSettings => 'Как в настройках';

  @override
  String get toolbarChipOff => 'Выкл.';

  @override
  String get toolbarChipFollowConnection => 'Как в подключении';

  @override
  String get gridEditBlockedReadOnly =>
      'Подключение только для чтения — редактирование ячеек отключено.';

  @override
  String get gridEditBlockedNoTable =>
      'Не удалось определить целевую таблицу — нужно запросить одну таблицу.';

  @override
  String gridEditsCount(Object count, Object rows) {
    return 'изменений: $count в строках: $rows';
  }

  @override
  String get gridCommitButton => 'Применить изменения';

  @override
  String get gridDiscardButton => 'Отменить изменения';

  @override
  String gridCommitSuccess(Object rows) {
    return 'Записано строк: $rows';
  }

  @override
  String gridCommitNoPrimaryKey(Object table) {
    return 'Таблица $table не имеет первичного ключа — запись невозможна.';
  }

  @override
  String gridCommitFailed(Object error) {
    return 'Ошибка записи: $error';
  }

  @override
  String get statusBarReady => 'Готово';

  @override
  String get statusBarExecuting => 'Выполнение';

  @override
  String statusBarElapsed(String duration) {
    return 'Прошло $duration';
  }

  @override
  String statusBarLineCol(int line, int column) {
    return 'Стр $line, Стб $column';
  }

  @override
  String executionStatusBarRows(int count) {
    return 'строк: $count';
  }

  @override
  String get executionStatusBarErrorHint =>
      'Нажмите на вкладку результата, чтобы увидеть подробности ошибок';

  @override
  String get toolbarExecutionPlan => 'План выполнения';

  @override
  String get toolbarFormat => 'Форматировать';

  @override
  String get toolbarSave => 'Сохранить';

  @override
  String get splitButton => 'Разделить';

  @override
  String get horizontalSplit => 'Горизонтальное разделение';

  @override
  String get verticalSplit => 'Вертикальное разделение';

  @override
  String get refreshData => 'Обновить данные';

  @override
  String get analyzingDatabasePerformance =>
      'Анализ производительности базы данных...';

  @override
  String get fullTableScanDetected => 'Обнаружено полное сканирование таблицы';

  @override
  String get fullTableScanDesc =>
      'Запрос использует полное сканирование (type=ALL), рекомендуется индекс для WHERE столбцов';

  @override
  String get timeThreshold => 'Порог времени:';

  @override
  String get searchPlaceholder => 'Поиск...';

  @override
  String get closeBtn => 'Закрыть';

  @override
  String get apiSettingsSavedMsg => 'Настройки API сохранены';

  @override
  String get resultsHeaderExport => 'Экспорт';

  @override
  String get resultsHeaderSearch => 'Поиск';

  @override
  String get resultsHeaderClear => 'Очистить';

  @override
  String get resultsHeaderSubmit => 'Отправить';

  @override
  String get connectionStatusConnected => 'Подключено';

  @override
  String get connectionStatusNotConnected => 'Не подключено';

  @override
  String get selectConnection => 'Выбрать подключение...';

  @override
  String get selectDatabase => 'Выбрать базу данных';

  @override
  String get aiQuickActionOptimizeSql => 'Оптимизировать SQL';

  @override
  String get aiQuickActionExplainQuery => 'Объяснить запрос';

  @override
  String get aiQuickActionGenerateInsert => 'Сгенерировать INSERT';

  @override
  String get aiQuickActionGenerateUpdate => 'Сгенерировать UPDATE';

  @override
  String get aiQuickActionGenerateDelete => 'Сгенерировать DELETE';

  @override
  String get aiQuickActionCreateTable => 'Создать таблицу';

  @override
  String get aiQuickActionSecurityCheck => 'Проверка безопасности';

  @override
  String get aiQuickActionIndexSuggestion => 'Предложение индекса';

  @override
  String get aiQuickActionExecutionPlan => 'План выполнения';

  @override
  String get aiQuickActionQueryHistory => 'История запросов';

  @override
  String get shortcutCategoryQuery => 'Запрос';

  @override
  String get queryCancelled => 'Запрос отменен';

  @override
  String queryFailed(Object error) {
    return 'Запрос неудался: $error';
  }

  @override
  String querySuccessWithTime(Object count, Object time) {
    return 'Запрос успешен, возвращено $count строк ($timeмс)';
  }

  @override
  String get cancelingQuery => 'Отмена запроса...';

  @override
  String get cancelQueryFailed => 'Не удалось отменить запрос';

  @override
  String get confirmCancelTransaction => 'Confirm Cancel Transaction';

  @override
  String get confirmCancelTransactionMessage =>
      'The current connection has an uncommitted transaction. Canceling the query will disconnect and reconnect, causing the transaction to rollback. Continue?';

  @override
  String get cancel => 'Cancel';

  @override
  String get explainPlanSuccess => 'План выполнения успешно получен';

  @override
  String explainPlanFailed(Object error) {
    return 'Не удалось получить план выполнения: $error';
  }

  @override
  String get queryEmptyCannotSave =>
      'Содержимое запроса пусто, невозможно сохранить';

  @override
  String get saveQueryTitle => 'Сохранить запрос';

  @override
  String get queryName => 'Название запроса';

  @override
  String get enterQueryName => 'Введите название запроса';

  @override
  String get saveQueryHint =>
      'Будет сохранено в списке сохраненных запросов (макс 20)';

  @override
  String querySaved(Object name) {
    return 'Запрос сохранен: $name';
  }

  @override
  String get saveQueryLimitReached =>
      'Достигнут лимит сохранения (20), сначала удалите некоторые запросы';

  @override
  String savedQueryNameExists(Object name) {
    return 'Имя сохраненного запроса \"$name\" уже существует для этого подключения';
  }

  @override
  String get sqlFormatted => 'SQL отформатирован';

  @override
  String get pleaseEnterSqlCode => 'Пожалуйста, введите SQL код';

  @override
  String get noConnectedServer => 'Нет подключенного сервера';

  @override
  String get split2Hint => 'Split 2 - Введите SQL запрос...';

  @override
  String get toolbarClose => 'Закрыть';

  @override
  String connectedToServer(Object serverName) {
    return 'Подключено к $serverName';
  }

  @override
  String openTableDataFailed(Object error) {
    return 'Ошибка открытия данных таблицы: $error';
  }

  @override
  String queryTable(Object tableName) {
    return 'Запрос $tableName';
  }

  @override
  String openViewFailed(Object error) {
    return 'Ошибка открытия представления: $error';
  }

  @override
  String queryView(Object viewName) {
    return 'Запрос $viewName';
  }

  @override
  String openProcedureFailed(Object error) {
    return 'Ошибка открытия хранимой процедуры: $error';
  }

  @override
  String callProcedure(Object procName) {
    return 'Вызов $procName';
  }

  @override
  String get cancelConnection => 'Отменить подключение';

  @override
  String get deleteConnectionTitle => 'Удалить подключение';

  @override
  String deleteConnectionConfirm(Object serverName) {
    return 'Вы уверены, что хотите удалить подключение \"$serverName\"?';
  }

  @override
  String get refresh => 'Обновить';

  @override
  String get createNewTable => 'Создать новую таблицу';

  @override
  String get erDiagram => 'ER-диаграмма';

  @override
  String get properties => 'Свойства';

  @override
  String get exportStructure => 'Экспорт структуры';

  @override
  String get dropDatabase => 'Удалить базу данных';

  @override
  String get confirmDeleteDatabase => 'Удалить базу данных';

  @override
  String get confirmDropTable => 'Удалить таблицу';

  @override
  String typeNameToConfirm(String name) {
    return 'Введите \"$name\" для подтверждения';
  }

  @override
  String dropDatabaseWarning(String name) {
    return 'База данных \"$name\" будет удалена безвозвратно.';
  }

  @override
  String objectCountWarning(int count, String type) {
    return '$count $type будет уничтожено';
  }

  @override
  String get allDataWillBeLost => 'Все данные будут потеряны';

  @override
  String copiedDbStructureToClipboard(Object dbName) {
    return 'Структура $dbName скопирована в буфер обмена';
  }

  @override
  String databaseDeleted(Object dbName) {
    return 'База данных $dbName удалена';
  }

  @override
  String get browseData => 'Просмотр данных';

  @override
  String get editTable => 'Редактировать таблицу';

  @override
  String get copyTableName => 'Копировать имя таблицы';

  @override
  String get copyColumnName => 'Копировать имя столбца';

  @override
  String get copyIndexName => 'Копировать имя индекса';

  @override
  String get dropColumn => 'Удалить столбец';

  @override
  String get editIndex => 'Изменить индекс';

  @override
  String get dropIndex => 'Удалить индекс';

  @override
  String confirmDropColumn(Object column, Object table) {
    return 'Удалить столбец \"$column\" из таблицы \"$table\"?';
  }

  @override
  String confirmDropIndex(Object index) {
    return 'Удалить индекс \"$index\"?';
  }

  @override
  String columnDropped(Object column) {
    return 'Столбец \"$column\" удалён';
  }

  @override
  String indexDropped(Object index) {
    return 'Индекс \"$index\" удалён';
  }

  @override
  String dropColumnFailed(Object error) {
    return 'Ошибка удаления столбца: $error';
  }

  @override
  String dropIndexFailed(Object error) {
    return 'Ошибка удаления индекса: $error';
  }

  @override
  String get loadingSchema => 'Загрузка...';

  @override
  String get noColumns => 'Нет столбцов';

  @override
  String get noIndexes => 'Нет индексов';

  @override
  String get noProgrammableObjects =>
      'Этот тип базы данных не поддерживает программируемые объекты';

  @override
  String get exportData => 'Экспорт данных';

  @override
  String get dataSync => 'Синхронизация данных';

  @override
  String get rename => 'Переименовать';

  @override
  String get truncate => 'Очистить данные';

  @override
  String get dropTable => 'Удалить таблицу';

  @override
  String loadTableStructureFailed(Object error) {
    return 'Ошибка загрузки структуры таблицы: $error';
  }

  @override
  String get tableNameCopied => 'Имя таблицы скопировано';

  @override
  String copiedTableDataToClipboard(Object tableName) {
    return 'Данные таблицы $tableName скопированы в буфер обмена';
  }

  @override
  String tableRenamedTo(Object newName) {
    return 'Таблица переименована в $newName';
  }

  @override
  String renameFailed(Object error) {
    return 'Ошибка переименования: $error';
  }

  @override
  String tableTruncated(Object tableName) {
    return 'Таблица $tableName очищена';
  }

  @override
  String truncateFailed(Object error) {
    return 'Ошибка очистки: $error';
  }

  @override
  String tableDeleted(Object tableName) {
    return 'Таблица $tableName удалена';
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
  String get indexTypeNormal => 'Обычный';

  @override
  String get indexTypeUnique => 'Уникальный';

  @override
  String get hintIndexColumns => 'Например: id, name';

  @override
  String get pleaseDefineAtLeastOneColumn =>
      'Пожалуйста, определите хотя бы один столбец';

  @override
  String tableCreated(Object tableName) {
    return 'Таблица $tableName успешно создана';
  }

  @override
  String createFailed(Object error) {
    return 'Ошибка создания: $error';
  }

  @override
  String get tableModified => 'Таблица успешно изменена';

  @override
  String modifyFailed(Object error) {
    return 'Ошибка изменения: $error';
  }

  @override
  String get noInformation => 'Нет информации';

  @override
  String get truncateTableData => 'Очистить данные таблицы';

  @override
  String get menuCut => 'Вырезать';

  @override
  String get menuCopy => 'Копировать';

  @override
  String get menuPaste => 'Вставить';

  @override
  String get menuSelectAll => 'Выбрать все';

  @override
  String get menuFormatSql => 'Форматировать SQL';

  @override
  String get menuExecuteQuery => 'Выполнить запрос';

  @override
  String get commandNewConnection => 'Новое подключение';

  @override
  String get commandNewTab => 'Новая вкладка';

  @override
  String get commandExecuteQuery => 'Выполнить запрос';

  @override
  String get commandFormatSql => 'Форматировать SQL';

  @override
  String get commandToggleAiPanel => 'Переключить панель ИИ';

  @override
  String get commandQueryHistory => 'История запросов';

  @override
  String get commandShortcuts => 'Горячие клавиши';

  @override
  String get commandSettings => 'Настройки';

  @override
  String get commandCategoryHistory => 'История';

  @override
  String get commandCategoryHelp => 'Справка';

  @override
  String get commandDescNewConnection =>
      'Создать новое подключение к базе данных';

  @override
  String get commandDescNewTab => 'Создать новую вкладку запроса';

  @override
  String get commandDescExecuteQuery => 'Выполнить текущий SQL-запрос';

  @override
  String get commandDescFormatSql => 'Форматировать SQL-код';

  @override
  String get commandDescToggleSidebar => 'Показать или скрыть боковую панель';

  @override
  String get commandDescToggleAiPanel =>
      'Показать или скрыть панель ИИ-ассистента';

  @override
  String get commandDescQueryHistory => 'Просмотреть историю выполнения';

  @override
  String get commandDescShortcuts => 'Просмотреть все горячие клавиши';

  @override
  String get commandDescSettings => 'Открыть настройки приложения';

  @override
  String get searchNavigateKeys => '↑↓/Мышь';

  @override
  String get menuConnect => 'Подключиться';

  @override
  String get menuCancelConnection => 'Отменить подключение';

  @override
  String get menuDisconnect => 'Отключиться';

  @override
  String get menuRefresh => 'Обновить';

  @override
  String get menuEditConnection => 'Редактировать подключение';

  @override
  String get menuCloneConnection => 'Клонировать подключение';

  @override
  String get menuDeleteConnection => 'Удалить подключение';

  @override
  String get addColumn => 'Добавить столбец';

  @override
  String get addIndex => 'Добавить индекс';

  @override
  String get noIndexesClickToAdd =>
      'Нет индексов, нажмите кнопку выше, чтобы добавить';

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
      'CSV - универсальный формат электронных таблиц, совместимый с Excel, Numbers, Google Sheets и другими инструментами.';

  @override
  String get formatJSONDesc =>
      'JSON - формат структурированных данных, подходящий для чтения программами или вызовов API.';

  @override
  String get formatExcelDesc =>
      'Формат Excel сохраняет типы данных и форматирование, подходя для глубокого анализа данных.';

  @override
  String get formatMarkdownDesc =>
      'Формат таблиц Markdown подходит для документов, отчетов или использования в проверках кода.';

  @override
  String get formatSqlInsertDesc =>
      'Инструкции SQL INSERT можно напрямую импортировать в другие базы данных, подходя для миграции данных.';

  @override
  String get copiedToClipboard => 'Скопировано в буфер обмена';

  @override
  String get hintFormatName => 'Например: Мой формат';

  @override
  String get hintOptionalDescription => 'Описание (необязательно)';

  @override
  String get formatterSelectPreset => 'Выбрать предустановку';

  @override
  String get formatterFormat => 'Форматировать';

  @override
  String get formatterCopyResult => 'Копировать результат';

  @override
  String get formatterHintInputSql => 'Введите SQL-код здесь...';

  @override
  String get formatterSpace => 'Пробел';

  @override
  String get formatterTab => 'Tab';

  @override
  String get formatterIndentSize => 'Размер отступа';

  @override
  String get formatterMaxLineLength => 'Максимальная длина строки';

  @override
  String get formatterUppercaseKeywords => 'Ключевые слова в верхнем регистре';

  @override
  String get formatterAlignKeywords => 'Выровнять ключевые слова';

  @override
  String get formatterPreserveComments => 'Сохранить комментарии';

  @override
  String get formatterNewlineBeforeParentheses => 'Новая строка перед скобками';

  @override
  String get formatterCompactMode => 'Компактный режим';

  @override
  String get formatterPosition => 'Позиция';

  @override
  String get formatterEnd => 'Конец';

  @override
  String get formatterStart => 'Начало';

  @override
  String loadFailed(Object error) {
    return 'Ошибка загрузки';
  }

  @override
  String exportFailed(String error) {
    return 'Ошибка экспорта: $error';
  }

  @override
  String timeAgoDays(Object count) {
    return '$count дней назад';
  }

  @override
  String timeAgoHours(Object count) {
    return '$count часов назад';
  }

  @override
  String timeAgoMinutes(Object count) {
    return '$count минут назад';
  }

  @override
  String get timeAgoJustNow => 'Только что';

  @override
  String get optimizationFullTableScan => 'Полное сканирование таблицы';

  @override
  String get optimizationFullTableScanDesc =>
      'Запрос использует полное сканирование (type=ALL), рекомендуется добавить индекс';

  @override
  String get optimizationFilesort => 'Сортировка файлов';

  @override
  String get optimizationFilesortDesc =>
      'Запрос использует сортировку файлов (Using filesort), рекомендуется оптимизировать';

  @override
  String get optimizationTemporary => 'Временная таблица';

  @override
  String get optimizationTemporaryDesc =>
      'Запрос использует временные таблицы (Using temporary), рекомендуется оптимизировать';

  @override
  String get optimizationLowEfficiency => 'Низкая эффективность';

  @override
  String optimizationLowEfficiencyDesc(
    Object ratio,
    Object rowsExamined,
    Object rowsSent,
  ) {
    return 'Низкая эффективность сканирования, рассмотрите возможность добавления индекса';
  }

  @override
  String get optimizationNoIssue => 'Нет проблем';

  @override
  String get optimizationNoIssueDesc => 'План выполнения выглядит нормально';

  @override
  String get optimizationSuggestions => 'Предложения по оптимизации';

  @override
  String get indexTypeDistribution => 'Распределение типов индексов';

  @override
  String get noData => 'Нет данных';

  @override
  String get indexPrimary => 'Первичный';

  @override
  String get indexUnique => 'Уникальный';

  @override
  String get indexNormal => 'Обычный';

  @override
  String get totalIndexes => 'Всего индексов';

  @override
  String get indexUsed => 'Использовано';

  @override
  String get indexUnused => 'Не использовано';

  @override
  String indexCount(Object count) {
    return 'Количество индексов';
  }

  @override
  String columnCardinality(Object cardinality) {
    return 'Кардинальность столбца';
  }

  @override
  String columnsLabel(Object columns) {
    return 'Столбцы';
  }

  @override
  String get totalTables => 'Всего таблиц';

  @override
  String get totalRows => 'Всего строк';

  @override
  String get dataSize => 'Размер данных';

  @override
  String get indexSize => 'Размер индексов';

  @override
  String get tableSizeDistribution => 'Распределение размеров таблиц';

  @override
  String get tableNameLabel => 'Имя таблицы';

  @override
  String get tableEngineLabel => 'Движок';

  @override
  String get tableRowCountLabel => 'Количество строк';

  @override
  String get tableDataSizeLabel => 'Размер данных';

  @override
  String get tableIndexSizeLabel => 'Размер индексов';

  @override
  String get tableTotalSizeLabel => 'Общий размер';

  @override
  String get tableRatioLabel => 'Процент';

  @override
  String get databasePerformanceReport =>
      'Отчет о производительности базы данных';

  @override
  String databaseLabel(Object name) {
    return 'База данных';
  }

  @override
  String generatedAtLabel(Object time) {
    return 'Сгенерировано';
  }

  @override
  String get tableCountLabel => 'Количество таблиц';

  @override
  String get slowQueryCountLabel => 'Количество медленных запросов';

  @override
  String get suggestionCountLabel => 'Количество предложений';

  @override
  String impactLevel(Object level) {
    return 'Уровень влияния';
  }

  @override
  String get impactHigh => 'Высокий';

  @override
  String get impactMedium => 'Средний';

  @override
  String get impactLow => 'Низкий';

  @override
  String get recommendedAction => 'Рекомендуемое действие';

  @override
  String slowQueryTopN(Object count) {
    return 'Топ медленных запросов';
  }

  @override
  String get largeTableStats => 'Статистика больших таблиц';

  @override
  String get tabRenameTitle => 'Переименовать запрос';

  @override
  String get tabRenameHint => 'Введите имя запроса';

  @override
  String get tabRename => 'Переименовать';

  @override
  String get tabClose => 'Закрыть';

  @override
  String get tabCloseOthers => 'Закрыть другие';

  @override
  String get tabCloseToRight => 'Закрыть справа';

  @override
  String get tabCloseAll => 'Закрыть все';

  @override
  String get tabDuplicate => 'Дублировать вкладку';

  @override
  String get tabNewTooltip => 'Новый запрос (Ctrl+T)';

  @override
  String tabNewQueryTitle(Object count) {
    return 'Запрос $count';
  }

  @override
  String get confirm => 'Подтвердить';

  @override
  String get copySuffix => '(Копия)';

  @override
  String get triggerTitle => 'Триггеры';

  @override
  String triggerFailedToLoad(Object error) {
    return 'Не удалось загрузить триггеры: $error';
  }

  @override
  String get triggerFailedToLoadDefinition =>
      'Не удалось загрузить определение триггера';

  @override
  String get triggerDeleteTitle => 'Удалить триггер';

  @override
  String triggerDeleteConfirm(Object name) {
    return 'Вы уверены, что хотите удалить триггер \"$name\"?';
  }

  @override
  String triggerDeleted(Object name) {
    return 'Триггер \"$name\" удален';
  }

  @override
  String triggerDeleteFailed(Object error) {
    return 'Не удалось удалить триггер: $error';
  }

  @override
  String get triggerCannotDisable =>
      'Триггеры MySQL нельзя отключить напрямую. Используйте Удалить для удаления.';

  @override
  String get triggerShowList => 'Показать список';

  @override
  String get triggerGroupByTable => 'Группировать по таблице';

  @override
  String get triggerSearchHint => 'Поиск триггеров...';

  @override
  String get triggerNoTriggers => 'Триггеры не найдены';

  @override
  String get triggerCreate => 'Создать триггер';

  @override
  String get triggerViewDefinition => 'Посмотреть определение';

  @override
  String get triggerCopyName => 'Копировать имя';

  @override
  String triggerCopied(Object name) {
    return '\"$name\" скопирован в буфер обмена';
  }

  @override
  String get triggerNew => 'Новый триггер';

  @override
  String triggerDefinition(Object name) {
    return 'Триггер: $name';
  }

  @override
  String get formatterSqlFormat => 'Формат SQL';

  @override
  String get formatterSavePreset => 'Сохранить пресет';

  @override
  String get formatterPresetName => 'Название пресета';

  @override
  String get formatterCustomPreset => 'Пользовательский пресет';

  @override
  String get formatterBuiltIn => 'Встроенный';

  @override
  String get formatterSaveAsPreset => 'Сохранить текущие настройки как пресет';

  @override
  String get formatterDeletePreset => 'Удалить пресет';

  @override
  String get formatterInput => 'Ввод';

  @override
  String get formatterOptions => 'Параметры форматирования';

  @override
  String get formatterIndent => 'Отступ';

  @override
  String get formatterKeywords => 'Ключевые слова';

  @override
  String get formatterCommaStyle => 'Стиль запятой';

  @override
  String get formatterApplyToEditor => 'Применить к редактору';

  @override
  String filterTitle(String columnName) {
    return 'Фильтр: $columnName';
  }

  @override
  String get filterEquals => 'равно';

  @override
  String get filterNotEquals => 'не равно';

  @override
  String get filterContains => 'содержит';

  @override
  String get filterNotContains => 'не содержит';

  @override
  String get filterGreaterThan => 'больше';

  @override
  String get filterLessThan => 'меньше';

  @override
  String get filterIsEmpty => 'пусто';

  @override
  String get filterIsNotEmpty => 'не пусто';

  @override
  String get filterRegex => 'regex';

  @override
  String get filterValue => 'Значение';

  @override
  String get filterEnterValue => 'Введите значение фильтра';

  @override
  String get filterCaseSensitive => 'Учитывать регистр';

  @override
  String get filterTimeFilter => 'Фильтр по времени';

  @override
  String get filterToday => 'Сегодня';

  @override
  String get filterLast24Hours => 'Последние 24 часа';

  @override
  String get filterLast7Days => 'Последние 7 дней';

  @override
  String get filterLast30Days => 'Последние 30 дней';

  @override
  String rowCountLabel(Object count) {
    return '$count строк';
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
  String get aiPanelCustomModel => 'Пользовательская модель';

  @override
  String get aiPanelBookmarks => 'Закладки';

  @override
  String get aiPanelScrollToMessageDeveloping =>
      'Функция прокрутки к сообщению в разработке';

  @override
  String get aiPanelBranchConversationCreated => 'Создана ветка разговора';

  @override
  String get aiPanelNoConnections =>
      'Нет подключений, создайте в управлении подключениями';

  @override
  String get aiPanelConversationList => 'Список разговоров';

  @override
  String get aiPanelSelectConnection => 'Выбрать подключение';

  @override
  String get aiPanelNoConnection => 'Нет подключения';

  @override
  String get aiPanelSelectDatabaseFirst => 'Сначала выберите подключение';

  @override
  String get aiPanelSelectDatabase => 'Выбрать базу данных';

  @override
  String get aiPanelAllDatabases => 'Все базы данных';

  @override
  String get aiPanelConnectionFailed => 'Ошибка подключения';

  @override
  String get aiPanelUnknownError => 'Неизвестная ошибка';

  @override
  String get aiPanelLoadDatabasesFailed => 'Не удалось загрузить базы данных';

  @override
  String get aiPanelDangerousOperation => 'Опасная операция';

  @override
  String get aiPanelOptimizeSql => 'Оптимизировать SQL';

  @override
  String get aiPanelSecurityAnalysis => 'Анализ безопасности';

  @override
  String get aiPanelExecutionPlan => 'План выполнения';

  @override
  String get aiPanelIndexSuggestions => 'Предложения индексов';

  @override
  String get aiPanelInputHint =>
      'Введите ваш вопрос о базе данных, например: Как оптимизировать этот запрос?';

  @override
  String get aiPanelStop => 'Стоп';

  @override
  String get aiPanelSend => 'Отправить';

  @override
  String get aiPanelSelectConnectionFirst =>
      'Пожалуйста, сначала выберите экземпляр подключения в раскрывающемся списке выше.';

  @override
  String aiPanelConnectionNotAvailable(Object name) {
    return 'Экземпляр подключения \"$name\" не подключен или недоступен, пожалуйста, сначала подключите его.';
  }

  @override
  String get aiPanelTable => 'Таблица';

  @override
  String get aiPanelDangerousOperationBadge => 'Опасная операция';

  @override
  String get aiPanelThinkingProcess => 'Процесс мышления';

  @override
  String get aiPanelExpandThinking => 'Развернуть процесс мышления';

  @override
  String get aiPanelCollapseThinking => 'Свернуть процесс мышления';

  @override
  String get aiPanelRenameSession => 'Переименовать разговор';

  @override
  String get aiPanelSessionTitle => 'Название разговора';

  @override
  String get aiPanelDeleteSession => 'Удалить разговор';

  @override
  String aiPanelDeleteSessionConfirm(Object name) {
    return 'Вы уверены, что хотите удалить \"$name\"?';
  }

  @override
  String get aiPanelRename => 'Переименовать';

  @override
  String get aiPanelUnarchive => 'Разархивировать';

  @override
  String get aiPanelArchive => 'Архивировать';

  @override
  String get aiPanelSessions => 'Разговоры';

  @override
  String get aiPanelSearchSessions => 'Поиск разговоров';

  @override
  String get aiPanelNoSessions => 'Нет разговоров';

  @override
  String aiPanelArchivedSessions(Object count) {
    return 'Архивированные разговоры ($count)';
  }

  @override
  String get aiPanelJustNow => 'Только что';

  @override
  String aiPanelMinutesAgo(Object count) {
    return '$count минут назад';
  }

  @override
  String aiPanelHoursAgo(Object count) {
    return '$count часов назад';
  }

  @override
  String aiPanelDaysAgo(Object count) {
    return '$count дней назад';
  }

  @override
  String get aiPanelSelectProvider => 'Выбрать провайдера';

  @override
  String aiPanelSelectModelCurrent(Object provider) {
    return 'Выбрать модель (Текущий: $provider)';
  }

  @override
  String aiPanelApiConfigCurrent(Object provider) {
    return 'Конфигурация API (Текущий: $provider)';
  }

  @override
  String get aiPanelModelProviderMismatch =>
      'Выбранная модель не принадлежит выбранному провайдеру';

  @override
  String get aiPanelAllowSession => 'Разрешить эту сессию';

  @override
  String get aiPanelNoBookmarks => 'Нет закладок';

  @override
  String get aiPanelClickBookmarkIcon =>
      'Нажмите на значок закладки сообщения, чтобы добавить';

  @override
  String get aiCmdOptimizeSql => 'Оптимизировать SQL-запрос';

  @override
  String get aiCmdExplainQuery => 'Объяснить план запроса';

  @override
  String get aiCmdGenerateCrud => 'Сгенерировать CRUD-операции';

  @override
  String get aiCmdAnalyzeTable => 'Анализировать структуру таблицы';

  @override
  String get aiCmdShowHistory => 'Просмотреть историю запросов';

  @override
  String get aiCmdShowBookmarks => 'Просмотреть закладки';

  @override
  String get aiCmdBranchConversation => 'Создать ветку разговора';

  @override
  String get aiCmdListDatabases => 'List all databases';

  @override
  String get aiCmdListTables => 'List all tables';

  @override
  String get settingsThemeMode => 'Режим темы';

  @override
  String get settingsThemeColor => 'Акцентный цвет';

  @override
  String get settingsSystem => 'Система';

  @override
  String get settingsPreview => 'Предпросмотр';

  @override
  String get settingsPrimaryButton => 'Основная кнопка';

  @override
  String get settingsSecondaryButton => 'Вторичная кнопка';

  @override
  String get settingsApply => 'Применить';

  @override
  String get colorBlue => 'Синий';

  @override
  String get colorPurple => 'Фиолетовый';

  @override
  String get colorGreen => 'Зелёный';

  @override
  String get colorOrange => 'Оранжевый';

  @override
  String get colorRed => 'Красный';

  @override
  String get colorCyan => 'Бирюзовый';

  @override
  String get colorPink => 'Розовый';

  @override
  String get colorYellow => 'Жёлтый';

  @override
  String get aiChatPageTitle => 'ИИ-помощник';

  @override
  String get messageLabelYou => 'Вы';

  @override
  String get messageLabelAi => 'ИИ';

  @override
  String get messageStatusSending => 'Отправка';

  @override
  String get messageStatusGenerating => 'Генерация';

  @override
  String get messageStatusFailed => 'Ошибка';

  @override
  String get messageStatusCancelled => 'Отменено';

  @override
  String get messageStatusError => 'Ошибка';

  @override
  String get messageStatusThinking => 'Размышление';

  @override
  String tokenUsagePrompt(int count) {
    return 'Вход $count';
  }

  @override
  String tokenUsageCompletion(int count) {
    return 'Выход $count';
  }

  @override
  String tokenUsageTotal(int count) {
    return 'Всего $count';
  }

  @override
  String sessionTokenUsage(
    int promptTokens,
    int completionTokens,
    int totalTokens,
  ) {
    return 'Сессия: Вход $promptTokens · Выход $completionTokens · Всего $totalTokens';
  }

  @override
  String get messageActionRegenerate => 'Перегенерировать';

  @override
  String get tooltipCopyCode => 'Копировать код';

  @override
  String get tooltipExecuteCode => 'Выполнить код';

  @override
  String get messageCopied => 'Скопировано';

  @override
  String toolCallTitle(String name) {
    return 'Инструмент: $name';
  }

  @override
  String toolResultTitle(String name) {
    return 'Результат: $name';
  }

  @override
  String get toolCallCompleted => 'Вызвано и завершено';

  @override
  String get toolParamLabel => 'Параметры';

  @override
  String get toolResultLabel => 'Результат';

  @override
  String get toolGroupTitle => 'Группа инструментов';

  @override
  String toolGroupSummary(int count) {
    return 'Выполнено $count инструментов';
  }

  @override
  String toolGroupItemTitle(int index, String name) {
    return 'Инструмент $index: $name';
  }

  @override
  String get toolNoParams => 'Нет параметров';

  @override
  String get aiWelcomeTitle => 'ИИ-помощник по базам данных';

  @override
  String get aiWelcomeDescription =>
      'Я могу помочь вам писать SQL, оптимизировать запросы, анализировать структуру таблиц, проверять безопасность или отвечать на любые вопросы о базах данных.';

  @override
  String aiConnectedTo(String name) {
    return 'Подключено: $name';
  }

  @override
  String get aiExampleSectionTitle => 'Попробуйте спросить меня';

  @override
  String get aiQuickActionsSectionTitle => 'Быстрые действия';

  @override
  String get aiTipQuickSend => 'Ctrl + Enter для отправки';

  @override
  String get aiTipSlashCommands => 'Введите / чтобы увидеть все команды';

  @override
  String get aiExampleQuestion1 =>
      'Оптимизировать производительность этого запроса';

  @override
  String get aiExampleQuestion2 => 'Анализировать текущую структуру таблицы';

  @override
  String get aiExampleQuestion3 => 'Проверить безопасность этого SQL';

  @override
  String get errorApiKeyRequired => 'Пожалуйста, сначала введите API Key';

  @override
  String get errorBaseUrlRequired => 'Пожалуйста, сначала введите Base URL';

  @override
  String errorFetchModelsFailed(String error) {
    return 'Не удалось получить список моделей: $error';
  }

  @override
  String get tooltipRefreshModels => 'Обновить список моделей';

  @override
  String get labelCustomModelInput => 'Ввести название модели вручную';

  @override
  String get tooltipAddModel => 'Добавить модель';

  @override
  String get hintFetchOrInputModel =>
      'Нажмите обновить для получения или введите название модели вручную';

  @override
  String get hintFetchModels => 'Нажмите обновить для получения списка моделей';

  @override
  String get errorSelectModelRequired =>
      'Пожалуйста, выберите или введите модель';

  @override
  String errorSaveFailed(String error) {
    return 'Ошибка сохранения: $error';
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
    return 'Выбран файл: $name';
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
  String get smartImportAiInferringTable => 'ИИ определяет имя таблицы...';

  @override
  String smartImportAiSuggestedTable(String name) {
    return 'ИИ предлагает имя таблицы: $name';
  }

  @override
  String get smartImportDoNotImport => 'Не импортировать';

  @override
  String smartImportTaskDescription(int count, String table) {
    return 'Импорт $count в $table';
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
  String get smartImportAiModel => 'AI Модель';

  @override
  String get aiPanelFullscreen => 'Полноэкранный режим';

  @override
  String get aiPanelExitFullscreen => 'Выйти из полноэкранного режима';

  @override
  String get aiPanelOpenInNewQuery => 'Открыто в новом запросе';

  @override
  String aiPanelInsertStatementsGenerated(int count, String tableName) {
    return 'ИИ сгенерировал $count INSERT-выражений, готовых к вставке в таблицу [$tableName].';
  }

  @override
  String get aiPanelSqlPreviewTitle => 'Предпросмотр SQL (первые 3):';

  @override
  String aiPanelMoreStatements(int count) {
    return '... и еще $count выражений';
  }

  @override
  String aiAgentToolCallLimitReached(int count) {
    return 'ИИ-ассистент достиг лимита вызовов инструментов ($count раз). Пожалуйста, упростите ваш вопрос или действуйте пошагово.';
  }

  @override
  String get aiAgentMaxIterationsReached =>
      'Агент достиг максимального количества итераций и не смог завершить разговор.';

  @override
  String get aiAgentDuplicateQuery =>
      'Этот запрос уже был выполнен. Пожалуйста, ответьте напрямую на основе существующих результатов, не повторяя запрос.';

  @override
  String aiAgentToolExecutionFailed(String error) {
    return 'Ошибка выполнения инструмента: $error';
  }

  @override
  String aiAgentUnknownTool(String name) {
    return 'Неизвестный инструмент: $name';
  }

  @override
  String aiContextCurrentDatabase(String name) {
    return 'Текущая база данных: $name';
  }

  @override
  String aiContextCurrentTable(String name) {
    return 'Текущая таблица: $name';
  }

  @override
  String aiContextRecentQueries(String queries) {
    return 'Недавние запросы: $queries';
  }

  @override
  String aiContextGoalSummary(String summary) {
    return 'Краткое описание цели текущей сессии: $summary';
  }

  @override
  String get taskPanelTitle => 'Задачи';

  @override
  String get taskPanelEmpty => 'Нет задач';

  @override
  String get taskPanelEmptyDesc =>
      'Операции импорта или экспорта будут отображаться здесь';

  @override
  String get taskPanelClearCompleted => 'Очистить завершенные';

  @override
  String get taskPanelStatusPending => 'В ожидании';

  @override
  String get taskPanelStatusRunning => 'Выполняется';

  @override
  String get taskPanelStatusPaused => 'Приостановлено';

  @override
  String get taskPanelStatusCompleted => 'Завершено';

  @override
  String get taskPanelStatusFailed => 'Ошибка';

  @override
  String get taskPanelStatusCancelled => 'Отменено';

  @override
  String get taskTypeImport => 'Импорт';

  @override
  String get taskTypeExport => 'Экспорт';

  @override
  String get taskTypeQuery => 'Запрос';

  @override
  String get taskActionCancel => 'Отменить';

  @override
  String get taskActionRetry => 'Повторить';

  @override
  String get taskActionRemove => 'Удалить';

  @override
  String get taskActionOpenFolder => 'Открыть папку';

  @override
  String get taskCreateExportTitle => 'Создать задачу экспорта';

  @override
  String get taskCreateExportFormat => 'Формат экспорта';

  @override
  String get taskCreateExportPath => 'Путь вывода';

  @override
  String get taskCreateExportPathPlaceholder =>
      'Нажмите кнопку справа, чтобы выбрать место сохранения';

  @override
  String get taskCreateExportPathSelect => 'Выбрать место сохранения';

  @override
  String get taskCreateExportStart => 'Создать задачу';

  @override
  String get taskValidationPathRequired => 'Пожалуйста, выберите путь вывода';

  @override
  String get taskValidationPathNotWritable =>
      'Каталог недоступен для записи, выберите другое место';

  @override
  String get taskValidationPathExists =>
      'Файл уже существует и будет перезаписан';

  @override
  String taskStatusBarTasks(int count) {
    return '$count задач';
  }

  @override
  String taskStatusBarRunning(int count) {
    return '$count выполняется';
  }

  @override
  String get taskLogInfo => 'Информация';

  @override
  String get taskLogWarning => 'Предупреждение';

  @override
  String get taskLogError => 'Ошибка';

  @override
  String get taskLogSuccess => 'Успех';

  @override
  String get taskDetailTitle => 'Детали задачи';

  @override
  String get taskDetailBasicInfo => 'Основная информация';

  @override
  String get taskDetailStatistics => 'Статистика выполнения';

  @override
  String get taskDetailError => 'Сообщение об ошибке';

  @override
  String get taskDetailOutputFile => 'Выходной файл';

  @override
  String get taskDetailLogs => 'Журналы выполнения';

  @override
  String get taskDetailCopied => 'Путь скопирован в буфер обмена';

  @override
  String get taskPhaseAnalyzing => 'Анализируется...';

  @override
  String get taskPhaseQuerying => 'Запрос данных...';

  @override
  String get taskPhaseFormatting => 'Форматирование данных...';

  @override
  String get taskPhaseWriting => 'Запись файла...';

  @override
  String get taskPhaseCompleted => 'Завершено';

  @override
  String get aiExportButtonCreate => 'Создать задачу экспорта';

  @override
  String get aiExportButtonAnalyzing => 'Анализируется...';

  @override
  String get aiMessageExportAction => 'Экспортировать эти данные';

  @override
  String get smartImportCreateTask => 'Создать задачу импорта в фоновом режиме';

  @override
  String get schemaDiffTitle => 'Сравнение и синхронизация схемы';

  @override
  String get schemaDiffMenuItem => 'Сравнение и синхронизация схемы';

  @override
  String get schemaDiffSource => 'Источник';

  @override
  String get schemaDiffTarget => 'Цель';

  @override
  String get schemaDiffCompareButton => 'Сравнить';

  @override
  String get schemaDiffSelectDatabases =>
      'Выберите исходную и целевую базы данных для сравнения';

  @override
  String get schemaDiffTabOverview => 'Обзор';

  @override
  String get schemaDiffTabDetails => 'Детали';

  @override
  String get schemaDiffTabSync => 'Синхронизация';

  @override
  String get sidebarColumns => 'Столбцы';

  @override
  String get sidebarIndexes => 'Индексы';

  @override
  String get sidebarInsertIntoEditor => 'Вставить в редактор';

  @override
  String get sidebarForeignKeys => 'Внешние ключи';

  @override
  String get sidebarCopyIndexName => 'Копировать имя индекса';

  @override
  String get sidebarCopyForeignKeyName => 'Копировать имя внешнего ключа';

  @override
  String get sidebarCopyName => 'Копировать имя';

  @override
  String get sidebarReadOnlyConnection => 'Подключение только для чтения';

  @override
  String get sidebarCopyColumnName => 'Копировать имя столбца';

  @override
  String get sidebarCopyColumnType => 'Копировать тип столбца';

  @override
  String get sidebarCopyAllColumnNames => 'Копировать все имена столбцов';

  @override
  String get sidebarOpenEditorFirst => 'Сначала откройте вкладку запроса';

  @override
  String get sidebarEvents => 'События';

  @override
  String get sidebarProgrammableObjects => 'Программируемые объекты';

  @override
  String get selectDatabaseHint =>
      'Дважды щёлкните по базе данных, чтобы просмотреть её объекты';

  @override
  String get workspaceEmptyTitle => 'Нет открытых запросов';

  @override
  String get workspaceEmptyHint =>
      'Создайте новую вкладку запроса, чтобы начать работу';

  @override
  String get noSearchResults => 'Совпадений не найдено';

  @override
  String get page => 'Страница';

  @override
  String get settingsSubscriptionSettings => 'Подписка';

  @override
  String get settingsFreePlan => 'Бесплатно';

  @override
  String get settingsFreePlanDesc => 'Вы используете бесплатный тариф';

  @override
  String get settingsProActivated => 'Pro активирован';

  @override
  String get settingsProActivatedDesc => 'Все функции Pro разблокированы';

  @override
  String get settingsUpgradeToPro => 'Обновить до Pro';

  @override
  String get settingsRestorePurchases => 'Восстановить покупки';

  @override
  String get purchaseDialogTitle => 'Обновить до Pro';

  @override
  String get purchaseDialogDesc =>
      'Разблокируйте все премиум-функции с подпиской Pro';

  @override
  String get purchaseDialogNoProducts => 'Нет доступных продуктов';

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
  String get recentTables => 'Недавние';

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
  String get unsavedChangesTitle => 'Несохранённые изменения';

  @override
  String get unsavedChangesMessage =>
      'Эта вкладка содержит несохранённые изменения. Закрыть без сохранения?';

  @override
  String get discardChanges => 'Не сохранять';

  @override
  String tabCloseConfirmMessage(String title) {
    return 'Сохранить изменения в «$title» перед закрытием?';
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
  String get exportConnectionsTitle => 'Экспорт подключений';

  @override
  String get importConnectionsTitle => 'Импорт подключений';

  @override
  String get exportConnectionsCount => 'Подключений для экспорта';

  @override
  String get exportPasswordHint => 'Пароль резервной копии';

  @override
  String get confirmExportPasswordHint => 'Подтвердите пароль резервной копии';

  @override
  String get passwordsDoNotMatch => 'Пароли не совпадают';

  @override
  String get importPasswordHint => 'Пароль резервной копии';

  @override
  String get selectExportFile => 'Сохранить в файл';

  @override
  String get selectImportFile => 'Выбрать файл резервной копии';

  @override
  String selectImportFileFailed(String error) {
    return 'Не удалось выбрать файл: $error';
  }

  @override
  String get conflictStrategyLabel => 'Если имя подключения уже существует';

  @override
  String get conflictStrategySkip => 'Пропустить';

  @override
  String get conflictStrategyRename => 'Переименовать';

  @override
  String get conflictStrategyOverwrite => 'Перезаписать';

  @override
  String get exportSuccess => 'Подключения успешно экспортированы';

  @override
  String get importSuccess => 'Подключения успешно импортированы';

  @override
  String get invalidPassword => 'Неверный пароль';

  @override
  String get invalidFile =>
      'Недействительный или поврежденный файл резервной копии';

  @override
  String get noConnectionsToExport => 'Нет подключений для экспорта';

  @override
  String get exportThisConnection => 'Экспортировать это подключение';

  @override
  String get commandCategoryTools => 'Инструменты';

  @override
  String get passwordRequiredTitle => 'Требуется пароль';

  @override
  String passwordRequiredMessage(String serverName) {
    return 'Введите пароль для $serverName, чтобы подключиться';
  }

  @override
  String get connectionConnectNoPassword => 'Подключиться без пароля';

  @override
  String get embeddedRequiresRemoteServer => 'Только удалённый сервер';

  @override
  String get serverSessionExpiredTitle => 'Сессия истекла';

  @override
  String get serverSessionExpiredMessage =>
      'Сессия сервера истекла или была отозвана. Войдите снова, чтобы продолжить.';

  @override
  String get serverSessionRelogin => 'Войти снова';

  @override
  String get serverReconnectLastSession => 'Подключиться к последнему серверу';

  @override
  String get serverReconnectFailed =>
      'Сохранённая сессия больше недействительна. Войдите снова.';

  @override
  String sidebarEmptyTableFailed(String error) {
    return 'Failed to empty table: $error';
  }

  @override
  String sidebarDropViewFailed(String error) {
    return 'Не удалось удалить представление: $error';
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
    return 'Удалить представление \"$viewName\"?\n\nДействие необратимо.';
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
  String get sidebarBrowseData => 'Просмотр данных';

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
  String get connectionMongoMode => 'Режим подключения';

  @override
  String get connectionMongoModeDirect => 'Прямое (один узел)';

  @override
  String get connectionMongoModeReplicaSet => 'Replica Set';

  @override
  String get connectionMongoSeedHosts => 'Узлы инициализации';

  @override
  String get connectionMongoSeedHostsHint =>
      'Перечислите все узлы replica set (host:port, по одному на строку). Драйвер сам находит primary; этот список — источник истины.';

  @override
  String get connectionMongoSeedHostsRequired =>
      'Требуется хотя бы один узел (host:port)';

  @override
  String get connectionMongoReplicaSetName => 'Имя Replica Set';

  @override
  String get connectionMongoReplicaSetNameRequired => 'Укажите имя Replica Set';

  @override
  String get connectionMongoModeAdvanced => 'Расширенный (строка подключения)';

  @override
  String get connectionMongoModeSharded => 'Шардированный (mongos)';

  @override
  String get connectionMongoMongosHosts => 'Маршрутизаторы mongos';

  @override
  String get connectionMongoMongosHostsHint =>
      'Перечислите все узлы mongos (host:port, по одному на строку). Драйвер подключается через mongos; шардирование прозрачно.';

  @override
  String get connectionMongoMongosHostsRequired =>
      'Требуется хотя бы один маршрутизатор mongos (host:port)';

  @override
  String get connectionMongoInvalidHostPort =>
      'Некорректная запись (ожидался host или host:port)';

  @override
  String get connectionMongoConnectionString => 'Строка подключения';

  @override
  String get connectionMongoConnectionStringHint =>
      'Вставьте полную строку подключения (mongodb:// или mongodb+srv://, вкл. Atlas). Учётные данные удаляются автоматически; пароль хранится отдельно в зашифрованном виде.';

  @override
  String get connectionMongoConnectionStringRequired =>
      'Вставьте строку подключения';

  @override
  String get connectionMongoConnectionStringInvalid =>
      'Некорректная строка подключения (должна начинаться с mongodb:// или mongodb+srv://)';

  @override
  String get connInvalidPort => 'Invalid port';

  @override
  String get connUsernameRequired => 'Требуется имя пользователя';

  @override
  String get connNameRequired => 'Требуется имя подключения';

  @override
  String get connHostRequired => 'Требуется хост';

  @override
  String get connPortRequired => 'Требуется порт';

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
    return 'Не удалось удалить: $error';
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
  String get bottomPanelTabHistory => 'История';

  @override
  String get bottomPanelTabTasks => 'Задачи';

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
  String get dmlCriticalTitle => 'Критическая операция';

  @override
  String get dmlHighWarningTitle => 'Операция высокого риска';

  @override
  String get dmlHighWarningBody =>
      'Эта операция затронет все подходящие строки. Рекомендуется добавить LIMIT.';

  @override
  String get dmlAddLimit => 'Добавить LIMIT';

  @override
  String get dmlConfirmExecute => 'Подтвердить выполнение';

  @override
  String get dmlRiskSummary => 'Сводка рисков';

  @override
  String get dmlStatementsToExecute => 'Операторы для выполнения:';

  @override
  String dmlEstimatedAffectedRows(Object count) {
    return 'Ожидаемое число затронутых строк: $count';
  }

  @override
  String dmlSqlInjectionDetail(Object details) {
    return 'SQL-инъекция: $details';
  }

  @override
  String get dmlTriggerDeleteWithoutWhere => 'DELETE без предложения WHERE';

  @override
  String get dmlTriggerUpdateWithoutWhere => 'UPDATE без предложения WHERE';

  @override
  String get dmlTriggerDropTable => 'Операция DROP TABLE';

  @override
  String get dmlTriggerDropDatabase => 'Операция DROP DATABASE';

  @override
  String get dmlTriggerTruncateTable => 'Операция TRUNCATE TABLE';

  @override
  String get dmlTriggerDmlWithoutLimit => 'DML без предложения LIMIT';

  @override
  String get dmlTriggerAlterDropColumn => 'ALTER TABLE DROP COLUMN';

  @override
  String get dmlTriggerSqlInjection => 'Обнаружен шаблон SQL-инъекции';

  @override
  String dropTableDeleteConfirmBody(Object tableName) {
    return 'Вы уверены, что хотите удалить таблицу \"$tableName\"?';
  }

  @override
  String get dropTableDeleteImpact =>
      'Эта операция необратима. Все данные в таблице будут удалены безвозвратно.';

  @override
  String get dropTableCheckingDependencies => 'Проверка зависимостей...';

  @override
  String get dropTableDependencyWarning => 'Предупреждение о зависимостях';

  @override
  String get connectionReadOnlyMode => 'Режим только чтения';

  @override
  String get connectionReadOnlyModeDesc =>
      'Запретить операции INSERT/UPDATE/DELETE/DDL';

  @override
  String get connectionSshHost => 'SSH-хост';

  @override
  String get connectionSshUsername => 'Имя пользователя SSH';

  @override
  String get connectionSshPassword => 'Пароль SSH';

  @override
  String get connSshHostRequired => 'Укажите SSH-хост';

  @override
  String get commonNavigate => 'Навигация';

  @override
  String get resultsSqlStatementLabel => 'Оператор SQL:';

  @override
  String get resultsExecutionSuccess => 'Выполнено успешно';

  @override
  String resultsAffectedRows(Object count) {
    return 'Затронуто строк: $count';
  }

  @override
  String resultsElapsedMs(Object ms) {
    return 'Время: $ms мс';
  }

  @override
  String resultsFilterConditions(Object count) {
    return 'Активных фильтров: $count';
  }

  @override
  String resultsShowingRows(Object filtered, Object total) {
    return 'Показано $filtered из $total строк';
  }

  @override
  String get resultsClearFilter => 'Сбросить фильтры';

  @override
  String get resultsNoDataGuidance =>
      'Напишите запрос в редакторе и нажмите Ctrl+Enter (или F5), чтобы выполнить его';

  @override
  String get queryHistoryEmptyHint =>
      'Выполните запрос с помощью Ctrl+Enter или F5 — он автоматически появится здесь';

  @override
  String get safetyExplainWarning => 'Предупреждение о производительности';

  @override
  String safetyExplainFullScan(Object rows) {
    return 'Обнаружено полное сканирование таблицы. Ожидается $rows строк.';
  }

  @override
  String get safetyExecuteAnyway => 'Всё равно выполнить';

  @override
  String get safetyCancelAndOptimize => 'Отмена и просмотр плана выполнения';

  @override
  String get safetyPreflightTimeout =>
      'Время предварительной проверки истекло. Анализ производительности пропущен.';

  @override
  String get dmlAuditBlocked => 'Операция DML заблокирована';

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
  String get processManagerTitle => 'Диспетчер процессов';

  @override
  String get processListNoProcesses => 'No active processes';

  @override
  String get processListNoQueryText => 'Нет текста запроса';

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
  String get mongoNodeReplication => 'Репликация';

  @override
  String get mongoNodeSharding => 'Шардирование';

  @override
  String get mongoValidationRules => 'Правила валидации';

  @override
  String get mongoReplicationStandalone =>
      'Автономный - не часть набора реплик';

  @override
  String get mongoShardingNotSharded => 'Не шардированный кластер';

  @override
  String get mongoValidationNoRules => 'Нет правил валидации';

  @override
  String get resultColumnTruncated =>
      'Значение может быть усечено (тип больших объектов)';

  @override
  String get dorisUpdateGuardMessage =>
      'Таблицы Doris с моделью Duplicate/Aggregate не поддерживают UPDATE; только модели Unique/Primary Key.';

  @override
  String get dorisTableModelLabel => 'Модель таблицы';

  @override
  String get dorisModelDuplicate => 'Duplicate';

  @override
  String get dorisModelUnique => 'Unique';

  @override
  String get dorisModelPrimaryKey => 'Primary Key';

  @override
  String get dorisHashColumnLabel => 'Хэш-столбец';

  @override
  String get dorisBucketsLabel => 'Buckets';

  @override
  String get dorisModelNeedsKeyColumn =>
      'Эта модель требует хотя бы один ключевой столбец (отметьте Primary Key у столбца)';

  @override
  String get dorisAggregateFunctionLabel => 'Функция агрегации';

  @override
  String get dorisModelAggregate => 'Aggregate';

  @override
  String get dorisPartitionColumn => 'Столбец раздела';

  @override
  String get dorisPartitionName => 'Имя раздела';

  @override
  String get dorisPartitionLessThan => 'Значения меньше';

  @override
  String get dorisAddPartition => 'Добавить раздел';

  @override
  String get offlineLicenseTitle => 'Офлайн-лицензия';

  @override
  String get offlineLicensePurchaseHint =>
      'Для обновления: отсканируйте платёжный код на странице GitHub/Gitee, затем отправьте код машины и скриншот оплаты автору. Вы получите лицензию для импорта ниже.';

  @override
  String get machineCodeLabel => 'Код машины';

  @override
  String get machineCodeUnavailable =>
      'Не удалось прочитать код машины на этом устройстве';

  @override
  String get importLicense => 'Импортировать лицензию';

  @override
  String get importLicenseHint =>
      'Вставьте строку лицензии или выберите файл .dbmlicense';

  @override
  String get buyLicense => 'Купить лицензию';

  @override
  String get machineCodeCopied => 'Код устройства скопирован в буфер обмена';

  @override
  String get licenseFilePick => 'Выбрать файл';

  @override
  String get licenseTypeYearly => 'Годовая подписка';

  @override
  String get licenseTypeLifetime => 'Бессрочная';

  @override
  String licenseExpiresAt(String date) {
    return 'Истекает: $date';
  }

  @override
  String get removeLicense => 'Удалить лицензию';

  @override
  String get licenseImportSuccess =>
      'Лицензия активирована — Pro-функции разблокированы';

  @override
  String get licenseErrorInvalid => 'Неверный формат лицензии';

  @override
  String get licenseErrorSignature => 'Ошибка проверки подписи лицензии';

  @override
  String get licenseErrorMachine => 'Эта лицензия привязана к другой машине';

  @override
  String get licenseErrorExpired => 'Срок действия лицензии истёк';

  @override
  String get licenseErrorNoMachine =>
      'Не удалось прочитать код машины; офлайн-лицензия недоступна';

  @override
  String licenseActiveInfo(String email) {
    return 'Лицензия для $email';
  }

  @override
  String get errorCopy => 'Копировать';

  @override
  String get errorCopied => 'Скопировано';

  @override
  String get errorAnalyzeWithAi => 'Анализ с ИИ';

  @override
  String trialRemaining(int count, String feature) {
    return 'Осталось $count пробных использований для $feature';
  }

  @override
  String trialUsedUp(String feature) {
    return 'Проба $feature исчерпана';
  }

  @override
  String get centerTitle => 'Центр выполнения';

  @override
  String get centerTabTasks => 'Задачи';

  @override
  String get centerTabErrors => 'Ошибки';

  @override
  String get centerClearErrors => 'Очистить ошибки';

  @override
  String get centerDismissError => 'Скрыть';

  @override
  String get aiPromptErrorHeader =>
      'Диагностируйте эту ошибку базы данных: объясните причину и предложите исправление.';

  @override
  String get commonUndo => 'Отменить';

  @override
  String commonDeleteWithCount(Object count) {
    return 'Удалить ($count)';
  }

  @override
  String aiPanelSessionsDeletedCount(Object count) {
    return 'Удалено $count бесед';
  }

  @override
  String aiPanelSessionDeleted(Object title) {
    return 'Удалено «$title»';
  }

  @override
  String get aiPanelSelectDatabaseRequired =>
      'Сначала выберите базу данных из выпадающего списка выше.';

  @override
  String get aiPanelMongoExecutionPlan => '🔍 План выполнения Mongo';

  @override
  String get aiPanelSelectSessions => 'Выбрать беседы';

  @override
  String get aiPanelExportTaskCreated => 'Задача экспорта успешно создана';

  @override
  String get aiPanelDdlOperationCancelled =>
      'Операция DDL отменена пользователем.';

  @override
  String get aiAssistantOpenTooltip => 'Открыть AI-ассистент';

  @override
  String get schemaImpactRiskLow => 'Низкий риск';

  @override
  String get schemaImpactRiskMedium => 'Средний риск';

  @override
  String get schemaImpactRiskHigh => 'Высокий риск';

  @override
  String get schemaImpactRiskCritical => 'Критический риск';

  @override
  String get schemaImpactTitle => 'Анализ влияния на схему';

  @override
  String schemaImpactSubtitle(Object table, Object type) {
    return '$type для `$table`';
  }

  @override
  String get schemaImpactDataLossWarning =>
      'Риск потери данных: эта операция безвозвратно удалит данные.';

  @override
  String schemaImpactAffectedObjects(Object count) {
    return 'Затронутые объекты ($count)';
  }

  @override
  String schemaImpactWarnings(Object count) {
    return 'Предупреждения ($count)';
  }

  @override
  String get schemaImpactRecommendations => 'Рекомендации';

  @override
  String get schemaImpactHideRollbackScript => 'Скрыть скрипт отката';

  @override
  String get schemaImpactShowRollbackScript => 'Показать скрипт отката';

  @override
  String get schemaImpactNoRollbackAvailable => 'Откат недоступен';

  @override
  String get schemaImpactRollbackCaveat =>
      'Авто-сгенерированный откат — черновик best-effort: типы колонок и ограничения могут быть неверными. Проверьте перед выполнением; данные автоматически не восстанавливаются.';

  @override
  String get schemaImpactBackupRequired =>
      'Перед откатом необходимо создать резервную копию данных';

  @override
  String get schemaImpactConfirmationRequired =>
      'Эта операция требует вашего явного подтверждения перед выполнением.';

  @override
  String get ddlConfirmDialogTitle => 'Требуется подтверждение DDL';

  @override
  String ddlAffectedObjectsCount(Object count) {
    return 'Затронутые объекты ($count)';
  }

  @override
  String get ddlExecuteButton => 'Выполнить DDL';

  @override
  String get ddlSqlStatementLabel => 'SQL-инструкция:';

  @override
  String ddlRiskLevelLabel(Object level) {
    return 'Уровень риска: $level';
  }

  @override
  String get ddlDataLossRiskDetected => 'Обнаружен риск потери данных';

  @override
  String ddlWarningsCount(Object count) {
    return 'Предупреждения ($count)';
  }

  @override
  String get ddlTypeConfirmationToProceed =>
      'Введите подтверждение, чтобы продолжить';

  @override
  String ddlTypeToConfirmDestructive(Object token) {
    return 'Введите «$token», чтобы подтвердить эту разрушительную операцию:';
  }

  @override
  String get commonUnknown => 'Неизвестно';

  @override
  String get commonDismiss => 'Закрыть';

  @override
  String get readOnlyModeBlocked =>
      'Это подключение в режиме «только чтение»; операции записи отключены.';

  @override
  String get dlgFillVariables => 'Заполните переменные';

  @override
  String dlgVariableRequired(String variable) {
    return 'Введите $variable';
  }

  @override
  String get dlgEditTrigger => 'Редактировать триггер';

  @override
  String get dlgCreateTrigger => 'Создать триггер';

  @override
  String triggerLoadTablesFailed(String error) {
    return 'Не удалось загрузить таблицы: $error';
  }

  @override
  String get triggerSelectTableRequired => 'Выберите таблицу';

  @override
  String get triggerSelectEventRequired => 'Выберите хотя бы одно событие';

  @override
  String get triggerUpdated => 'Триггер успешно обновлён';

  @override
  String get triggerCreated => 'Триггер успешно создан';

  @override
  String triggerSaveFailed(String error) {
    return 'Не удалось сохранить триггер: $error';
  }

  @override
  String get triggerNameLabel => 'Имя триггера';

  @override
  String get triggerNameRequired => 'Имя триггера обязательно';

  @override
  String get triggerNameInvalid => 'Недопустимый формат имени триггера';

  @override
  String get triggerTimingLabel => 'Время срабатывания';

  @override
  String get triggerEventLabel => 'Событие';

  @override
  String get triggerTableLabel => 'Таблица';

  @override
  String get triggerSelectTableHint => 'Выберите таблицу';

  @override
  String get triggerBodyLabel => 'Тело триггера';

  @override
  String get triggerBodyHint =>
      'Введите тело триггера (SQL-операторы)\nПример:\nSET NEW.updated_at = NOW();';

  @override
  String triggerCount(int count) {
    return 'Триггеров: $count';
  }

  @override
  String get dlgExecutionResult => 'Результат выполнения';

  @override
  String dlgExecuteRoutine(String type) {
    return 'Выполнить $type';
  }

  @override
  String dlgRoutineName(String name) {
    return 'Имя: $name';
  }

  @override
  String dlgRoutineType(String type) {
    return 'Тип: $type';
  }

  @override
  String dlgRoutineReturnType(String type) {
    return 'Тип возвращаемого значения: $type';
  }

  @override
  String get dlgParameters => 'Параметры';

  @override
  String get dlgRoutineNoParams =>
      'Эта процедура/функция не требует параметров';

  @override
  String get dlgOutputParam => 'Выходной параметр';

  @override
  String get dlgReturnValueLabel => 'Возвращаемое значение:';

  @override
  String dlgRowsAffected(int count) {
    return 'Затронуто строк: $count';
  }

  @override
  String dlgEditRoutine(String type) {
    return 'Редактировать $type';
  }

  @override
  String routineParameterCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count параметров',
      few: '$count параметра',
      one: '1 параметр',
      zero: 'Нет параметров',
    );
    return '$_temp0';
  }

  @override
  String routineDeleteConfirmation(String type, String name) {
    return 'Удалить $type \"$name\"?';
  }

  @override
  String get routineListTitle => 'Процедуры и функции';

  @override
  String routineDefinitionTitle(String type) {
    return 'Определение $type';
  }

  @override
  String get queryExecutionPlan => 'План выполнения запроса';

  @override
  String dlgCreateRoutine(String type) {
    return 'Создать $type';
  }

  @override
  String get dlgNameRequired => 'Имя обязательно';

  @override
  String get dlgRoutineNameInvalid =>
      'Имя может содержать только буквы, цифры и подчёркивания и не может начинаться с цифры';

  @override
  String get dlgReturnTypeRequired => 'Выберите тип возвращаемого значения';

  @override
  String get dlgSqlCode => 'SQL-код';

  @override
  String get dlgRoutineProcedure => 'Хранимая процедура';

  @override
  String get dlgRoutineFunction => 'Функция';

  @override
  String get commonUpdate => 'Обновить';

  @override
  String get commonCreate => 'Создать';

  @override
  String get auditLogTitle => 'Журнал аудита запросов';

  @override
  String get auditLogAllStatus => 'Все статусы';

  @override
  String get auditLogAll => 'Все';

  @override
  String get auditLogTime => 'Время';

  @override
  String get auditLogDuration => 'Длительность';

  @override
  String get auditLogRows => 'Строки';

  @override
  String get auditLogStatus => 'Статус';

  @override
  String get auditLogEmpty => 'Журналов аудита пока нет';

  @override
  String get auditLogEmptyHint =>
      'Выполняйте запросы, чтобы начать запись журналов';

  @override
  String get auditLogTotal => 'Всего';

  @override
  String get auditLogWrite => 'Запись';

  @override
  String get auditLogAvgTime => 'Среднее время';

  @override
  String get auditLogClearTitle => 'Очистить журналы аудита';

  @override
  String get auditLogClearConfirm =>
      'Вы уверены, что хотите очистить все журналы аудита? Это действие нельзя отменить.';

  @override
  String get auditLogClear => 'Очистить';

  @override
  String get piiMaskingTitle => 'Маскирование персональных данных';

  @override
  String get piiMaskingEnable => 'Включить маскирование PII';

  @override
  String get piiMaskingEnableDesc =>
      'Автоматически маскировать конфиденциальные данные в результатах запросов';

  @override
  String get piiMaskingTypes => 'Типы конфиденциальных данных';

  @override
  String get piiTypeEmail => 'Адреса электронной почты';

  @override
  String get piiTypePhone => 'Номера телефонов';

  @override
  String get piiTypeIdCard => 'Удостоверения личности';

  @override
  String get piiTypeCreditCard => 'Кредитные карты';

  @override
  String get piiTypeBankCard => 'Банковские счета';

  @override
  String get piiTypePassword => 'Пароли';

  @override
  String get piiTypeIpAddress => 'IP-адреса';

  @override
  String get shortcutNoMatching => 'Подходящих сочетаний клавиш нет';

  @override
  String get shortcutPressEscToClose => 'Нажмите ESC для закрытия';

  @override
  String get indexTypePrimary => 'Первичный';

  @override
  String get performanceAnalyzerWeeklyReportTitle =>
      'Еженедельные отчёты о медленных запросах';

  @override
  String get performanceAnalyzerWeeklyReportDesc =>
      'Получайте топ-10 медленных запросов с анализом EXPLAIN каждый понедельник';

  @override
  String get performanceAnalyzerLearnMore => 'Подробнее';

  @override
  String get backupListLoading => 'Загрузка списка резервных копий...';

  @override
  String dbPropertiesTitle(String name) {
    return 'Свойства базы данных - $name';
  }

  @override
  String get dbPropertyName => 'Имя';

  @override
  String get dbPropertyCharset => 'Кодировка';

  @override
  String get dbPropertyCollation => 'Правило сортировки';

  @override
  String get dbPropertySize => 'Размер';

  @override
  String get dbPropertyTableCount => 'Таблицы';

  @override
  String get dbPropertyViewCount => 'Представления';

  @override
  String get dbPropertyRoutineCount => 'Процедуры/Функции';

  @override
  String get exportFormatLabel => 'Формат экспорта';

  @override
  String exportRowCount(int count) {
    return 'Всего строк: $count';
  }

  @override
  String get taskCreateExportFilter => 'Фильтр';

  @override
  String get taskCreateExportEstRows => 'Примерное число строк';

  @override
  String get taskCreateExportValidating => 'Проверка...';

  @override
  String get taskCreateExportSaveDialogTitle =>
      'Выберите место сохранения файла экспорта';

  @override
  String taskValidationPathNotExists(String path) {
    return 'Каталог не существует: $path';
  }

  @override
  String taskCreateExportDesc(String table) {
    return 'Экспорт $table';
  }

  @override
  String taskCreateExportDescFiltered(String table) {
    return 'Экспорт $table (с фильтром)';
  }

  @override
  String get sqliteConnectionEditTitle => 'Редактировать подключение SQLite';

  @override
  String get sqliteConnectionNewTitle => 'Новое подключение SQLite';

  @override
  String get createSuperTableTitle => 'Создать супертаблицу';

  @override
  String get importWizardTitle => 'Мастер импорта данных';

  @override
  String dbCreateSuccess(String name) {
    return 'База данных «$name» успешно создана';
  }

  @override
  String get dbCreateFailed => 'Не удалось создать базу данных';

  @override
  String dbCreateError(String error) {
    return 'Ошибка: $error';
  }

  @override
  String get dbOperationCannotBeUndone => 'Это действие нельзя отменить!';

  @override
  String dropTablePermanentWarning(String table) {
    return 'Таблица «$table» и все её данные будут безвозвратно удалены.';
  }

  @override
  String get dropTableDataLossWarning =>
      'Это действие нельзя отменить! Все данные в этой таблице будут безвозвратно потеряны.';

  @override
  String get objectTypeTable => 'таблица';

  @override
  String get objectTypeView => 'представление';

  @override
  String get commonRemove => 'Удалить';

  @override
  String get commonRequired => 'Обязательно';

  @override
  String get commonInvalidIdentifier => 'Недопустимый идентификатор';

  @override
  String get mongoValidationJsonObject => 'JSON должен быть объектом';

  @override
  String mongoValidationInvalidJson(String error) {
    return 'Недопустимый JSON: $error';
  }

  @override
  String get settingsAutoLimitEnabledDesc =>
      'Автоматически добавлять LIMIT к запросам SELECT';

  @override
  String get sqliteConnectionInfo => 'Информация о подключении';

  @override
  String get sqliteNameHint => 'Моя база SQLite';

  @override
  String get connectionDirNotExists => 'Каталог не существует';

  @override
  String get indexSelectColumnRequired => 'Выберите хотя бы один столбец';

  @override
  String indexCreateFailed(String error) {
    return 'Не удалось создать индекс: $error';
  }

  @override
  String indexUpdateFailed(String error) {
    return 'Не удалось обновить индекс: $error';
  }

  @override
  String get indexNameRequired => 'Имя индекса обязательно';

  @override
  String get superTableTags => 'Теги';

  @override
  String get superTableCreated => 'Супертаблица успешно создана';

  @override
  String get redisLibNameCodeRequired => 'Имя библиотеки и код обязательны';

  @override
  String get redisAdapterNotAvailable => 'Адаптер Redis недоступен';

  @override
  String get redisLibraryCreated => 'Библиотека функций успешно создана';

  @override
  String redisLibraryCreateFailed(String error) {
    return 'Не удалось создать библиотеку: $error';
  }

  @override
  String get redisLibraryUsageHint => 'Используется в #!lua name=<library>';

  @override
  String get redisInsertExample => 'Вставить пример';

  @override
  String get redisCreateLibrary => 'Создать библиотеку';

  @override
  String redisKeyLoadFailed(String error) {
    return 'Не удалось загрузить данные ключа: $error';
  }

  @override
  String get redisKeyUpdated => 'Ключ успешно обновлён';

  @override
  String redisKeySaveFailed(String error) {
    return 'Не удалось сохранить ключ: $error';
  }

  @override
  String get redisKeySaveChanges => 'Сохранить изменения';

  @override
  String get serverConnectTitle => 'Подключиться к серверу';

  @override
  String get serverConnectUrl => 'URL сервера';

  @override
  String get serverUrlRequired => 'URL сервера обязателен';

  @override
  String get serverUrlInvalid =>
      'Недопустимый URL (напр. https://myserver:3000)';

  @override
  String get serverConnectEmail => 'Эл. почта';

  @override
  String get serverEmailRequired => 'Эл. почта обязательна';

  @override
  String get serverEmailInvalid => 'Недопустимый адрес эл. почты';

  @override
  String get serverPasswordRequired => 'Пароль обязателен';

  @override
  String get mongoValidationFixErrors =>
      'Исправьте ошибки JSON перед применением';

  @override
  String get mongoValidationApplied => 'Правила проверки успешно применены';

  @override
  String get mongoValidationRemoved => 'Правила проверки удалены';

  @override
  String get mongoValidationLevel => 'Уровень валидации';

  @override
  String get mongoValidationAction => 'Действие валидации';

  @override
  String mongoValidationApplyFailed(String error) {
    return 'Не удалось применить правила проверки: $error';
  }

  @override
  String get indexSelectColumns => 'Выбор столбцов';

  @override
  String get redisLibraryTitle => 'Создать библиотеку функций';

  @override
  String get redisLibraryNameLabel => 'Имя библиотеки';

  @override
  String get redisLibraryCreateFailedSyntax =>
      'Не удалось создать библиотеку (требуется Redis 7.0+, проверьте синтаксис)';

  @override
  String get redisLuaCodeLabel => 'Код Lua';

  @override
  String get redisReplaceExisting =>
      'Заменить существующую библиотеку с тем же именем (FUNCTION LOAD REPLACE)';

  @override
  String get redisLibraryInfoText =>
      'Имя библиотеки автоматически записывается в shebang #!lua. Код Lua должен содержать вызовы redis.register_function(). Не пишите shebang самостоятельно.';

  @override
  String get superTableCreateFailed => 'Не удалось создать супертаблицу';

  @override
  String get superTableColumns => 'Столбцы';

  @override
  String get errorTitle => 'Произошла ошибка';

  @override
  String get errorDescriptionLabel => 'Сведения об ошибке:';

  @override
  String get errorStackLabel => 'Трассировка стека:';

  @override
  String get columnFilterTypeNumeric => 'Числовой';

  @override
  String get columnFilterTypeDateTime => 'Дата/Время';

  @override
  String get columnFilterTypeText => 'Текст';

  @override
  String get columnFilterPlaceholderNumeric => 'Введите число';

  @override
  String get columnFilterPlaceholderDateTime =>
      'Введите дату (напр. 2024-01-01)';

  @override
  String get columnFilterPlaceholderText => 'Введите текст';

  @override
  String columnFilterFor(String columnName) {
    return 'Фильтр: $columnName';
  }

  @override
  String columnFilterActive(int count) {
    return 'Применено условий фильтра: $count';
  }

  @override
  String columnFilterRowCount(String filtered, String total) {
    return '$filtered / $total строк';
  }

  @override
  String get filterOpEquals => 'равно';

  @override
  String get filterOpNotEquals => 'не равно';

  @override
  String get filterOpContains => 'содержит';

  @override
  String get filterOpNotContains => 'не содержит';

  @override
  String get filterOpStartsWith => 'начинается с';

  @override
  String get filterOpEndsWith => 'заканчивается на';

  @override
  String get filterOpGreaterThan => 'больше';

  @override
  String get filterOpGreaterThanOrEqual => 'больше или равно';

  @override
  String get filterOpLessThan => 'меньше';

  @override
  String get filterOpLessThanOrEqual => 'меньше или равно';

  @override
  String get filterOpBetween => 'между';

  @override
  String get filterOpIsNull => 'равно null';

  @override
  String get filterOpIsNotNull => 'не равно null';

  @override
  String get filterOpIsEmpty => 'пусто';

  @override
  String get filterOpIsNotEmpty => 'не пусто';

  @override
  String get tableNoData => 'Нет данных';

  @override
  String tableRowCountTotal(String count) {
    return 'Всего строк: $count';
  }

  @override
  String get tableLargeDatasetHint =>
      '(Большой набор данных, прокрутите для загрузки)';

  @override
  String tableRowRange(String start, String end, String total) {
    return '$start-$end / $total строк';
  }

  @override
  String get importWizStepSelectFile => 'Выбор файла';

  @override
  String get importWizStepAnalyzeFile => 'Анализ файла';

  @override
  String get importWizStepColumnMapping => 'Сопоставление столбцов';

  @override
  String get importWizStepPreviewPII => 'Предпросмотр и PII';

  @override
  String get importWizStepConfirmImport => 'Подтверждение импорта';

  @override
  String importWizStepOf(String current, String total, String title) {
    return 'Шаг $current из $total: $title';
  }

  @override
  String get importWizTargetDatabase => 'Целевая база данных';

  @override
  String get importWizSelectDatabase => 'Выберите базу данных';

  @override
  String get importWizTargetTableOptional => 'Целевая таблица (необязательно)';

  @override
  String get importWizLetAiInfer => '-- Позволить ИИ определить имя таблицы --';

  @override
  String get importWizChooseFile => 'Нажмите для выбора или перетащите файл';

  @override
  String get importWizChangeFile => 'Сменить файл';

  @override
  String get importWizSupportedFormats =>
      'Поддерживаются форматы CSV, JSON, Excel, TSV';

  @override
  String get importWizFileUnknown => 'Неизвестно';

  @override
  String get importWizAiAnalyzing => 'ИИ анализирует файл...';

  @override
  String get importWizDetectingFormat =>
      'Определение формата, кодировки, типов полей...';

  @override
  String get importWizFileAnalysisResult => 'Результат анализа файла';

  @override
  String get importWizFormat => 'Формат';

  @override
  String get importWizEncoding => 'Кодировка';

  @override
  String get importWizFieldCount => 'Полей';

  @override
  String get importWizEstimatedRows => 'Примерно строк';

  @override
  String get importWizFileSize => 'Размер файла';

  @override
  String get importWizDelimiter => 'Разделитель';

  @override
  String get importWizDetectedFields => 'Обнаруженные поля';

  @override
  String get importWizAiSuggestion => 'Предложение ИИ';

  @override
  String importWizTargetTableName(String tableName) {
    return 'Целевая таблица: $tableName';
  }

  @override
  String get importWizNoAnalysisResult => 'Нет результатов анализа';

  @override
  String get importWizSelectFileFirst => 'Сначала выберите файл';

  @override
  String get importWizNoColumnMapping => 'Нет сопоставления столбцов';

  @override
  String get importWizGeneratingMapping => 'Генерация сопоставления...';

  @override
  String get importWizColumnMappingConfig => 'Настройка сопоставления столбцов';

  @override
  String importWizColumnsMapped(String mapped, String total) {
    return 'Сопоставлено $mapped/$total столбцов';
  }

  @override
  String get importWizMappingDescription =>
      'Сопоставьте столбцы файла со столбцами таблицы. Выберите «Пропустить», чтобы пропустить столбец.';

  @override
  String get importWizFileColumn => 'Столбец файла';

  @override
  String get importWizDatabaseColumn => 'Столбец БД';

  @override
  String get importWizType => 'Тип';

  @override
  String get importWizPiiDetection =>
      'Обнаружение конфиденциальных данных (PII)';

  @override
  String get importWizPiiDetectionMessage =>
      'Обнаружены следующие конфиденциальные поля. Подтвердите продолжение импорта:';

  @override
  String get importWizPiiAcknowledge => 'Я понимаю, продолжить импорт';

  @override
  String get importWizDataPreview => 'Предпросмотр данных';

  @override
  String importWizWarnings(String count) {
    return '$count предупреждений';
  }

  @override
  String importWizFirstRows(String count) {
    return 'Первые $count строк';
  }

  @override
  String get importWizSensitiveField => 'Конфиденциальное поле';

  @override
  String get importWizDataValidationWarnings =>
      'Предупреждения проверки данных';

  @override
  String importWizValidationRowFormat(String row, String col, String msg) {
    return 'Строка $row, Столбец $col: $msg';
  }

  @override
  String get importWizImportSummary => 'Сводка конфигурации импорта';

  @override
  String get importWizSummaryTargetDatabase => 'Целевая база данных';

  @override
  String get importWizSummaryTargetTable => 'Целевая таблица';

  @override
  String get importWizSummaryFile => 'Файл';

  @override
  String get importWizSummaryMappedColumns => 'Сопоставлено столбцов';

  @override
  String get importWizSummaryDataRows => 'Строк данных';

  @override
  String get importWizConflictStrategy => 'Стратегия разрешения конфликтов';

  @override
  String get importWizConflictSkip => 'Пропускать дубликаты';

  @override
  String get importWizConflictSkipDesc =>
      'При обнаружении дублирующего ключа пропустить строку и продолжить импорт';

  @override
  String get importWizConflictUpdate => 'Обновлять существующие строки';

  @override
  String get importWizConflictUpdateDesc =>
      'При обнаружении дублирующего ключа обновить существующие данные';

  @override
  String get importWizConflictAbort => 'Прервать импорт';

  @override
  String get importWizConflictAbortDesc =>
      'При обнаружении дублирующего ключа немедленно остановить импорт';

  @override
  String get importWizConflictSkipName => 'Skip duplicates';

  @override
  String get importWizConflictUpdateName => 'Update existing';

  @override
  String get importWizConflictAbortName => 'Abort';

  @override
  String get importWizImporting => 'Импорт...';

  @override
  String importWizRowsProgress(String imported, String total) {
    return '$imported/$total строк';
  }

  @override
  String importWizFailedRows(String count) {
    return 'Ошибок: $count строк';
  }

  @override
  String get importWizImportComplete => 'Импорт завершён!';

  @override
  String importWizImportFailed(String error) {
    return 'Ошибка импорта: $error';
  }

  @override
  String importWizImportSuccessMsg(String count) {
    return 'Успешно импортировано $count строк';
  }

  @override
  String get importWizImportErrorMsg => 'При импорте произошла ошибка';

  @override
  String get importWizPreviousStep => 'Назад';

  @override
  String get importWizClose => 'Закрыть';

  @override
  String get importWizStartImport => 'Начать импорт';

  @override
  String get importWizNextStep => 'Далее';

  @override
  String get importWizReimport => 'Импортировать заново';

  @override
  String importWizLoadDatabasesFailed(String error) {
    return 'Не удалось загрузить список баз данных: $error';
  }

  @override
  String importWizLoadTablesFailed(String error) {
    return 'Не удалось загрузить список таблиц: $error';
  }

  @override
  String importWizPickFileFailed(String error) {
    return 'Не удалось выбрать файл: $error';
  }

  @override
  String importWizAnalysisFailed(String error) {
    return 'Ошибка анализа: $error';
  }

  @override
  String importWizMappingFailed(String error) {
    return 'Не удалось создать сопоставление: $error';
  }

  @override
  String get importWizFileAnalysisFailed => 'Ошибка анализа файла';

  @override
  String get importWizImportFailedGeneric => 'Ошибка импорта';

  @override
  String get importWizNotSelected => 'Не выбрано';

  @override
  String get importWizNotSet => 'Не задано';

  @override
  String get importWizUnknown => 'Неизвестно';

  @override
  String get importWizPiiDetectionSummary => 'Обнаружение PII';

  @override
  String importWizSensitiveFieldCount(String count) {
    return '$count конфиденциальных полей';
  }

  @override
  String get smartImportAnalyzingDetail =>
      'ИИ определяет типы полей и генерирует инструкцию CREATE TABLE';

  @override
  String get smartImportColumnMapping => 'Сопоставление столбцов';

  @override
  String smartImportColumnsMapped(String mapped, String total) {
    return 'Сопоставлено $mapped/$total столбцов';
  }

  @override
  String get smartImportFileColumn => 'Столбец файла';

  @override
  String get smartImportTableColumn => 'Столбец таблицы';

  @override
  String get smartImportConflictResolution => 'Разрешение конфликтов';

  @override
  String get smartImportDataPreview => 'Предпросмотр данных';

  @override
  String smartImportFirstRows(String count) {
    return 'Первые $count строк';
  }

  @override
  String get smartImportBack => 'Назад';

  @override
  String get smartImportBackgroundTask => 'Фоновый импорт';

  @override
  String get smartImportFailedToGenerateSql =>
      '-- Не удалось сгенерировать инструкцию CREATE TABLE';

  @override
  String smartImportTargetTableSelected(String table) {
    return 'Выбрана целевая таблица: $table';
  }

  @override
  String smartImportTargetTableEntered(String table) {
    return 'Введена целевая таблица: $table';
  }

  @override
  String smartImportAnalysisFailed(String error) {
    return 'Ошибка анализа файла: $error';
  }

  @override
  String smartImportColumnMappingsComplete(String mapped, String total) {
    return 'Сопоставление завершено: $mapped/$total столбцов сопоставлено автоматически';
  }

  @override
  String smartImportPiiDetected(String types) {
    return 'Обнаружение PII: Найдены конфиденциальные поля - $types';
  }

  @override
  String get smartImportPiiNone =>
      'Обнаружение PII: Конфиденциальных полей не найдено';

  @override
  String smartImportPiiFailed(String error) {
    return 'Ошибка обнаружения PII: $error';
  }

  @override
  String smartImportPreviewGenerated(String count) {
    return 'Предпросмотр данных создан ($count строк)';
  }

  @override
  String smartImportPreviewFailed(String error) {
    return 'Ошибка создания предпросмотра: $error';
  }

  @override
  String smartImportMappingFailed(String error) {
    return 'Ошибка создания сопоставления: $error';
  }

  @override
  String importServiceStartImport(String table) {
    return 'Начало импорта в таблицу \"$table\"...';
  }

  @override
  String importServiceColumnMapping(String mapped, String total) {
    return 'Сопоставление: $mapped/$total столбцов';
  }

  @override
  String importServiceConflictStrategy(String strategy) {
    return 'Стратегия конфликтов: $strategy';
  }

  @override
  String get importServiceImporting => 'Начало импорта данных...';

  @override
  String importServiceBatchSuccess(String batch, String count) {
    return 'Пакет $batch: успешно импортировано $count строк';
  }

  @override
  String importServiceBatchInsertFailed(String count) {
    return 'Ошибка пакетной вставки ($count строк), попытка построчной вставки...';
  }

  @override
  String importServiceUpdateFailed(String error) {
    return 'Ошибка обновления: $error';
  }

  @override
  String importServiceDataTooLong(String row) {
    return 'Строка $row: данные слишком длинные, пропущена';
  }

  @override
  String importServiceRowInsertFailed(String row, String error) {
    return 'Строка $row: ошибка вставки: $error';
  }

  @override
  String importServiceBatchSkipped(String count) {
    return 'Пакет пропущен: $count строк (дубликаты)';
  }

  @override
  String importServiceBatchUpdated(String count) {
    return 'Пакет обновлён: $count строк';
  }

  @override
  String importServiceBatchFailed(String count) {
    return 'Пакет не удался: $count строк';
  }

  @override
  String importServicePhaseProgress(
    String imported,
    String skipped,
    String updated,
  ) {
    return 'Импортировано $imported, пропущено $skipped, обновлено $updated...';
  }

  @override
  String get importServiceImportCancelled => 'Импорт отменён';

  @override
  String importServiceFileReadFailed(String error) {
    return 'Ошибка чтения файла: $error';
  }

  @override
  String importServiceImportComplete(String imported, String failed) {
    return 'Импорт завершён! Успешно: $imported, Ошибок: $failed';
  }

  @override
  String taskExecutorAnalyzeFile(String path) {
    return 'Анализ файла: $path';
  }

  @override
  String taskExecutorFileFormat(String format, String encoding, String rows) {
    return 'Формат: $format, Кодировка: $encoding, Примерно строк: $rows';
  }

  @override
  String get taskExecutorTableNotExists =>
      'Таблица не существует, создаётся...';

  @override
  String get taskExecutorTableCreated => 'Таблица успешно создана';

  @override
  String get taskExecutorTableCreateFailed => 'Не удалось создать таблицу';

  @override
  String taskExecutorTableNotExistsError(String table) {
    return 'Целевая таблица \"$table\" не существует. Сначала создайте таблицу.';
  }

  @override
  String get taskExecutorNoColumnMapping =>
      'Нет пригодного сопоставления столбцов. Проверьте соответствие полей файла и таблицы.';

  @override
  String taskExecutorColumnMapping(String mapped, String total) {
    return 'Сопоставление: $mapped/$total столбцов';
  }

  @override
  String get taskExecutorStartImport => 'Начало импорта данных...';

  @override
  String taskExecutorImportComplete(String imported, String failed) {
    return 'Импорт завершён! Успешно: $imported, Ошибок: $failed';
  }

  @override
  String get taskExecutorImportFinished => 'Импорт завершён';

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
  String get viewModeTable => 'Таблица';

  @override
  String get viewModeChart => 'График';

  @override
  String get viewModeCard => 'Карта';

  @override
  String get viewModeDocument => 'Документы';

  @override
  String get viewModeJsonTree => 'JSON-дерево';

  @override
  String get viewModeKeyValue => 'Ключ-значение';

  @override
  String get documentExpand => 'Развернуть';

  @override
  String get documentCollapse => 'Свернуть';

  @override
  String documentExpandMore(int count) {
    return 'Развернуть ещё $count полей';
  }

  @override
  String jsonTreeItemCount(int count) {
    return '$count элементов';
  }

  @override
  String get keyValueField => 'Поле';

  @override
  String get keyValueValue => 'Значение';

  @override
  String keyValueFieldLabel(String field) {
    return 'Поле: $field';
  }

  @override
  String keyValueLengthLabel(int length) {
    return 'Длина: $length символов';
  }

  @override
  String get chartViewComingSoon => 'График (скоро)';

  @override
  String chartExportSuccess(String path) {
    return 'График сохранён в $path';
  }

  @override
  String chartExportFailed(String error) {
    return 'Ошибка экспорта графика: $error';
  }

  @override
  String chartSamplingNotice(int count) {
    return 'Большой набор данных: выбрано $count точек';
  }

  @override
  String get chartAiTrend => 'AI анализ тренда';

  @override
  String get chartTypeLine => 'Линия';

  @override
  String get chartTypeBar => 'Столбец';

  @override
  String get chartTypePie => 'Круг';

  @override
  String get chartTypeScatter => 'Точечный';

  @override
  String get statisticsPanelTitle => 'Статистика';

  @override
  String get exportStepBack => 'Назад';

  @override
  String get exportStepNext => 'Далее';

  @override
  String get noJsonDataToSample => 'Нет данных для выборки';

  @override
  String get noLeafNodes => 'Нет извлекаемых полей';

  @override
  String get fieldNotInAllRows => 'не во всех строках';

  @override
  String get commonRetry => 'Повторить';

  @override
  String get extensionNoAdapter => 'Нет адаптера';

  @override
  String get extensionNotPostgres => 'Не подключение PostgreSQL';

  @override
  String get extensionLoadFailed => 'Не удалось загрузить члены';

  @override
  String get extensionTypes => 'Типы';

  @override
  String get extensionFunctions => 'Функции';

  @override
  String get extensionOperators => 'Операторы';

  @override
  String get extensionSchema => 'Схема';

  @override
  String get extensionDescription => 'Описание';

  @override
  String get vectorLoadFailed => 'Не удалось загрузить векторные индексы';

  @override
  String get vectorNoAdapter => 'Нет адаптера';

  @override
  String get vectorNoIndexes => 'Векторные индексы не определены';

  @override
  String get jsonInvalidJson => 'Неверный JSON';

  @override
  String get jsonNoMatches => 'Нет совпадений';

  @override
  String get jsonSearchHint => 'Поиск ключей или значений…';

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
  String get mcpTokensMenuLabel => 'Токены MCP';

  @override
  String get mcpTokensTitle => 'Токены MCP';

  @override
  String get mcpTokensIntro =>
      'Долгоживущие токены для ИИ-клиентов (Claude Code, Cursor). Вставьте токен как Bearer token в MCP-конфигурацию клиента; можно отозвать в любой момент.';

  @override
  String get mcpTokensNotConnected =>
      'Подключитесь к серверу DbMaster, чтобы управлять токенами MCP.';

  @override
  String get mcpTokensEmpty =>
      'Токенов пока нет. Создайте один для своего ИИ-клиента.';

  @override
  String get mcpTokensNameHint => 'Имя токена (напр. claude-code-mac)';

  @override
  String get mcpTokensCreate => 'Создать';

  @override
  String mcpTokensOnceTitle(String name) {
    return 'Токен «$name» создан';
  }

  @override
  String get mcpTokensOnceWarning =>
      'Скопируйте его сейчас — из соображений безопасности он больше не будет показан. Используйте его как Bearer token в конфигурации MCP-клиента (напр. mcp.json).';

  @override
  String get mcpTokensCopy => 'Копировать';

  @override
  String get mcpTokensCopied => 'Токен скопирован в буфер обмена';

  @override
  String get mcpTokensDone => 'Готово';

  @override
  String mcpTokensLastUsed(String value) {
    return 'Последнее использование: $value';
  }

  @override
  String get mcpTokensNeverUsed => 'никогда';

  @override
  String get mcpTokensRevoke => 'Отозвать';

  @override
  String get mcpTokensRevokeTitle => 'Отозвать этот токен?';

  @override
  String mcpTokensRevokeBody(String name, String prefix) {
    return 'Клиенты, использующие «$name» ($prefix…), сразу перестанут работать. Это действие необратимо.';
  }

  @override
  String get serverConnectionsMenuLabel => 'Подключения сервера';

  @override
  String get serverConnectionsTitle => 'Подключения сервера';

  @override
  String get serverConnectionsIntro =>
      'Подключения к базам данных, зарегистрированные на сервере. Синхронизация данных, проверки здоровья и согласования DDL выполняются по ним; список подключений в боковой панели — отдельный.';

  @override
  String get serverConnectionsNotConnected => 'Нет подключения к серверу.';

  @override
  String get serverConnectionsEmpty =>
      'Пока нет подключений сервера. Добавьте одно, чтобы задачи синхронизации / проверки здоровья / согласования имели базу данных.';

  @override
  String get serverConnectionsAdd => 'Добавить';

  @override
  String get serverConnectionsEdit => 'Изменить';

  @override
  String get serverConnectionsDelete => 'Удалить';

  @override
  String get serverConnectionsKindCollab => 'совместное';

  @override
  String get serverConnectionsKindSourceDrift =>
      'источник drift (только чтение)';

  @override
  String get serverConnectionsDeleteTitle => 'Удалить подключение';

  @override
  String serverConnectionsDeleteBody(String name) {
    return 'Удалить подключение сервера «$name»?';
  }

  @override
  String serverConnectionsDeleteTaskWarning(num count) {
    return '$count задача(задач) ссылаются на это подключение и будут удалены (как источник) или отвязаны (как цель).';
  }

  @override
  String get serverConnFormCreateTitle => 'Добавить подключение сервера';

  @override
  String get serverConnFormEditTitle => 'Изменить подключение сервера';

  @override
  String get serverConnFormName => 'Название';

  @override
  String get serverConnFormType => 'Тип';

  @override
  String get serverConnFormHost => 'Хост';

  @override
  String get serverConnFormPort => 'Порт';

  @override
  String get serverConnFormUsername => 'Имя пользователя';

  @override
  String get serverConnFormPassword => 'Пароль';

  @override
  String get serverConnFormPasswordKeepHint =>
      'Оставьте пустым, чтобы сохранить сохранённый пароль';

  @override
  String get serverConnFormDatabase =>
      'База данных по умолчанию (необязательно)';

  @override
  String get serverConnFormSqlitePath => 'Путь к файлу базы данных';

  @override
  String get serverConnFormSave => 'Сохранить';

  @override
  String get serverConnFormRequired => 'Обязательно';

  @override
  String get serverConnFormInvalidPort => 'Порт должен быть числом';

  @override
  String get dataSyncConnectionNotOnServer =>
      'Выбранное подключение не зарегистрировано на сервере. Сначала добавьте его в «Подключения сервера», затем повторите.';

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
    return 'Предоставляется $plugin';
  }

  @override
  String get connectionDbIndex => 'Индекс базы данных';

  @override
  String get connectionAuthDatabase => 'База данных аутентификации';

  @override
  String get connectionRedisAuthNone => 'Без аутентификации';

  @override
  String get connectionRedisAuthNoneDesc => 'Аутентификация не требуется';

  @override
  String get connectionRedisAuthPasswordOnly => 'Только пароль';

  @override
  String get connectionRedisAuthPasswordOnlyDesc => 'Пароль AUTH (Redis < 6.0)';

  @override
  String get connectionRedisAuthUsernamePassword =>
      'Имя пользователя + пароль (ACL)';

  @override
  String get connectionRedisAuthUsernamePasswordDesc =>
      'AUTH имя пользователя пароль (Redis 6.0+ ACL)';

  @override
  String get connectionSshAuthPassword => 'Пароль';

  @override
  String get connectionSshAuthPrivateKey => 'Приватный ключ';

  @override
  String get sidebarCapabilityTitle => 'Возможности';

  @override
  String get sidebarCapGroupDatabaseObjects => 'Объекты базы данных';

  @override
  String get sidebarCapGroupAdvanced => 'Дополнительно';

  @override
  String get redisCapGroupKeyspace => 'Ключевое пространство';

  @override
  String get redisCapWorkbench => 'Консоль (Workbench)';

  @override
  String get redisCapPubsub => 'Pub/Sub';

  @override
  String get redisCapLua => 'Скрипты Lua';

  @override
  String get redisCapPipeline => 'Конвейер (Pipeline)';

  @override
  String get redisCapTransaction => 'Транзакция';

  @override
  String get redisCapMemoryAnalysis => 'Анализ памяти';

  @override
  String get redisCapKeyspaceNotifications => 'Уведомления keyspace';

  @override
  String get redisCapAcl => 'Управление ACL';

  @override
  String get redisCapConfig => 'Изменить конфигурацию';

  @override
  String get mongoValidationTitle => 'Правила валидации';

  @override
  String get mongoValidationNoValidator =>
      'У этой коллекции не настроены правила валидации (добавьте через collMod или оболочку MongoDB).';

  @override
  String mongoValidationLoadFailed(String error) {
    return 'Не удалось загрузить правила валидации: $error';
  }

  @override
  String sidebarDocumentInserted(String collection) {
    return 'Документ вставлен в $collection';
  }

  @override
  String get aiSkillCatalogTitle => 'Навыки';

  @override
  String get aiSkillGroupSql => 'SQL';

  @override
  String get aiSkillGroupData => 'Данные';

  @override
  String get aiSkillGroupSchema => 'Схема';

  @override
  String get aiSkillGroupOps => 'Эксплуатация';

  @override
  String get aiSkillNl2sqlName => 'Естественный язык в SQL';

  @override
  String get aiSkillNl2sqlDesc => 'Опишите задачу словами — получите SQL';

  @override
  String get aiSkillSqlExplainName => 'Разбор SQL';

  @override
  String get aiSkillSqlExplainDesc => 'Объяснение работы SQL-запроса';

  @override
  String get aiSkillSqlExplainPrompt =>
      'Объясни по шагам, что делает этот SQL-запрос:\n```\n\n```';

  @override
  String get aiSkillQueryOptimizerName => 'Оптимизация запросов';

  @override
  String get aiSkillQueryOptimizerDesc =>
      'Анализ медленного запроса и рекомендации';

  @override
  String get aiSkillQueryOptimizerPrompt =>
      'Проанализируй этот запрос на проблемы производительности и предложи оптимизации:\n```\n\n```';

  @override
  String get aiSkillDataCleaningName => 'Очистка данных';

  @override
  String get aiSkillDataCleaningDesc =>
      'Рекомендации по очистке «грязных» данных';

  @override
  String get aiSkillDataCleaningPrompt =>
      'Предложи шаги очистки «грязных» данных в моей таблице. Известные проблемы:';

  @override
  String get aiSkillImportMappingName => 'Сопоставление импорта';

  @override
  String get aiSkillImportMappingDesc =>
      'Сформируй сопоставление колонок для импорта данных';

  @override
  String get aiSkillImportMappingPrompt =>
      'Сформируй сопоставление колонок (JSON) для импорта файла в таблицу.\nКолонки источника:\nКолонки цели:';

  @override
  String get aiSkillSchemaAnalysisName => 'Анализ схемы';

  @override
  String get aiSkillSchemaAnalysisDesc => 'Ревизия текущей схемы и риски';

  @override
  String get aiSkillSchemaAnalysisPrompt =>
      'Проведи ревизию схемы текущей базы и укажи проектные риски и улучшения.';

  @override
  String get aiSkillSchemaDiffName => 'Помощник сравнения схем';

  @override
  String get aiSkillSchemaDiffDesc =>
      'Сравни два определения схемы и выдай diff';

  @override
  String get aiSkillSchemaDiffPrompt =>
      'Сравни следующие два определения схемы и выдай unified diff:\n<schema-a>\n\n</schema-a>\n<schema-b>\n\n</schema-b>';

  @override
  String get aiSkillIndexSuggestName => 'Рекомендации по индексам';

  @override
  String get aiSkillIndexSuggestDesc => 'Индексы для запроса или таблицы';

  @override
  String get aiSkillIndexSuggestPrompt =>
      'Предложи индексы для этого запроса и обоснуй:\n```\n\n```';

  @override
  String get aiSkillErrorDiagnosisName => 'Диагностика ошибок';

  @override
  String get aiSkillErrorDiagnosisDesc => 'Диагностика ошибки базы данных';

  @override
  String get aiSkillErrorDiagnosisPrompt =>
      'Диагностируй эту ошибку базы данных и предложи исправления:\n```\n\n```';

  @override
  String get aiSkillSlowQueryName => 'Анализ медленных запросов';

  @override
  String get aiSkillSlowQueryDesc =>
      'Анализ записей журнала медленных запросов';

  @override
  String get aiSkillSlowQueryPrompt =>
      'Проанализируй эту запись журнала медленных запросов и найди узкое место:\n```\n\n```';

  @override
  String get aiContextPanelTitle => 'Контекст';

  @override
  String get aiContextConnectionSection => 'Текущее подключение';

  @override
  String get aiContextDatabaseSection => 'Текущая база';

  @override
  String get aiContextNoConnection => 'Подключение не выбрано';

  @override
  String get aiContextSchemaContext => 'Прикладывать контекст схемы';

  @override
  String get aiContextSchemaContextDesc =>
      'При отправке прикладывать схемы таблиц текущей базы';

  @override
  String get aiPanelOpenSkillCatalog => 'Каталог навыков';

  @override
  String get aiPanelOpenContextPanel => 'Панель контекста';

  @override
  String get safetyBannerAddLimit => 'Добавить LIMIT';

  @override
  String safetyBannerCooldown(int seconds) {
    return 'Подтвердить (${seconds}s)';
  }

  @override
  String get safetyDmlAllRowsWarning =>
      'Эта операция затронет все совпадающие строки. Рекомендуется добавить предложение LIMIT.';

  @override
  String get safetySeverityHigh => 'Критично';

  @override
  String get safetySeverityMedium => 'Предупреждение';

  @override
  String get safetySeverityLow => 'Инфо';

  @override
  String get safetySeverityPolicy => 'Политика';

  @override
  String gateTitleSingle(int count) {
    return 'Подтверждение выполнения: в этом SQL $count риск(ов)';
  }

  @override
  String gateTitleMulti(int count, int total) {
    return 'Подтверждение выполнения: $count риск(ов) в $total инструкциях';
  }

  @override
  String get gateDdlImpactTitle => 'Анализ влияния DDL';

  @override
  String gateStatementLabel(int n) {
    return 'Инструкция $n';
  }

  @override
  String get gateSuggestionLabel => 'Предлагаемое исправление';

  @override
  String gateOverview(int total, int high, int medium, int low, int ok) {
    return '$total инструкций · Критично $high · Предупреждение $medium · Инфо $low · Чисто $ok';
  }

  @override
  String gateSkipHighRisk(int skip, int exec) {
    return 'Пропустить $skip критичных, выполнить $exec';
  }

  @override
  String get gateAllHighDisabled => 'Все критичные — нечего выполнять';

  @override
  String get gateApplySuggestions => 'Применить рекомендации';

  @override
  String get gateProceed => 'Всё равно выполнить';

  @override
  String get gateProceedAll => 'Всё равно выполнить все';

  @override
  String get gateCancelAll => 'Отменить все';

  @override
  String get settingsNavAppearance => 'Оформление';

  @override
  String get settingsNavAi => 'ИИ';

  @override
  String get settingsNavQuery => 'Запросы';

  @override
  String get settingsNavLanguage => 'Язык';

  @override
  String get settingsNavSecurity => 'Безопасность';

  @override
  String get settingsNavAbout => 'О программе';

  @override
  String get piiExportStepFormat => 'Формат';

  @override
  String get piiExportStepScan => 'Проверка PII';

  @override
  String get piiExportStepConfirm => 'Подтверждение';

  @override
  String get piiExportNoPiiTitle => 'Данные PII не обнаружены';

  @override
  String get piiExportNoPiiSubtitle =>
      'Все столбцы будут экспортированы без изменений';

  @override
  String piiExportDetectedCount(int count) {
    return 'Обнаружено столбцов с PII: $count';
  }

  @override
  String get piiExportHighSensitivity => '(высокая чувствительность)';

  @override
  String get piiExportKeep => 'Оставить';

  @override
  String get piiExportMask => 'Маскировать';

  @override
  String get piiExportHash => 'Хешировать';

  @override
  String get piiExportDrop => 'Удалить столбец';

  @override
  String get piiExportReadyTitle => 'Готово к экспорту';

  @override
  String get piiExportSummaryFormat => 'Формат';

  @override
  String get piiExportSummaryRows => 'Строки';

  @override
  String get piiExportSummaryPiiColumns => 'Обработано PII-столбцов';

  @override
  String get piiExportFootnote =>
      'Столбцы с PII будут обработаны согласно выбору; остальные экспортируются без изменений';

  @override
  String get serverBarNotConnected => 'Не подключено';

  @override
  String get serverBarConnecting => 'Подключение…';

  @override
  String get serverBarLocal => 'Локально';

  @override
  String get serverBarConnected => 'Подключено';

  @override
  String get serverBarReconnecting => 'Переподключение…';

  @override
  String serverBarReconnectingIn(int seconds) {
    return 'Повтор через $seconds с…';
  }

  @override
  String serverBarServerUrl(String url) {
    return 'Сервер: $url';
  }

  @override
  String get serverBarDisconnect => 'Отключиться';

  @override
  String get serverBarUnknownUser => 'Неизвестно';

  @override
  String get serverConnectUnexpectedError => 'Произошла непредвиденная ошибка.';

  @override
  String get cellViewerCopy => 'Копировать';

  @override
  String cellViewerChars(Object count) {
    return '$count символов';
  }

  @override
  String get slowQueryMenuLabel => 'Статистика медленных запросов';

  @override
  String get slowQueryDialogTitle => 'Статистика медленных запросов';

  @override
  String slowQueryScopeBanner(int thresholdMs) {
    return 'Записываются запросы через dbmaster/server медленнее $thresholdMs мс; при включённом собственном сборе slow log на экземпляре добавляются и медленные запросы самой базы (различаются по source).';
  }

  @override
  String get slowQueryWindow1h => 'Последний час';

  @override
  String get slowQueryWindow24h => 'Последние 24 часа';

  @override
  String get slowQueryWindow7d => 'Последние 7 дней';

  @override
  String get slowQuerySortTotalMs => 'Общее время';

  @override
  String get slowQuerySortCount => 'Количество';

  @override
  String get slowQuerySortAvgMs => 'Среднее время';

  @override
  String get slowQuerySortMaxMs => 'Макс. время';

  @override
  String get slowQueryAllConnections => 'Все соединения';

  @override
  String slowQueryDigestStats(int count, String total, String avg, String max) {
    return '$count вызовов · всего $total · ср. $avg · макс $max';
  }

  @override
  String slowQueryLastSeen(String time) {
    return 'последний $time';
  }

  @override
  String get slowQueryEmptyTitle => 'Нет медленных запросов';

  @override
  String get slowQueryEmptyBody =>
      'За этот период нет запросов выше порога выборки. Выполните что-то медленное через dbmaster и вернитесь.';

  @override
  String get slowQueryLoadFailed => 'Не удалось загрузить статистику.';

  @override
  String get slowQueryRetry => 'Повторить';

  @override
  String slowQueryLoadMore(int shown, int total) {
    return 'Показать ещё ($shown из $total)';
  }

  @override
  String get slowQueryStatusOk => 'ок';

  @override
  String get slowQueryStatusError => 'ошибка';

  @override
  String get slowQueryStatusCancelled => 'отменён';

  @override
  String get slowQueryDatabaseLabel => 'База данных';

  @override
  String get slowQueryNoPlaintext =>
      'Открытый SQL отключён на этом экземпляре (только digest).';

  @override
  String get slowQueryCopySql => 'Копировать SQL';

  @override
  String get slowQueryCopied => 'Скопировано';

  @override
  String get reportsMenuLabel => 'Отчёты';

  @override
  String get reportsDialogTitle => 'Отчёты';

  @override
  String get reportsGenerateButton => 'Создать недельный отчёт';

  @override
  String get reportsGeneratedToast => 'Недельный отчёт создан.';

  @override
  String get reportsExistingToast => 'Отчёт за эту неделю уже существует.';

  @override
  String get reportsEmptyTitle => 'Нет отчётов';

  @override
  String get reportsEmptyBody =>
      'Создайте недельный отчёт по медленным запросам вручную или дождитесь расписания.';

  @override
  String get reportsLoadFailed => 'Не удалось загрузить отчёты.';

  @override
  String get reportsRetry => 'Повторить';

  @override
  String reportsLoadMore(int shown, int total) {
    return 'Показать ещё ($shown из $total)';
  }

  @override
  String get reportsWindowLabel => 'Период';

  @override
  String get reportsTruncatedHint =>
      'Неполный период: более старые выборки уже удалены retention.';

  @override
  String get reportsSamplesLabel => 'Выборки';

  @override
  String get reportsDistinctLabel => 'Различных запросов';

  @override
  String get reportsTotalTimeLabel => 'Общее время';

  @override
  String get reportsErrorsLabel => 'Ошибки';

  @override
  String get reportsWowLabel => 'к прош. неделе';

  @override
  String get reportsTopSection => 'Топ запросов';

  @override
  String get reportsByDaySection => 'По дням';

  @override
  String get reportsByConnectionSection => 'По соединениям';

  @override
  String get reportsUnknownType =>
      'Неизвестный тип отчёта — исходное содержимое:';

  @override
  String get reportsAnalyzeWithAi => 'Анализировать с ИИ';
}
