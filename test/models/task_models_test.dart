import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/task_models.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

void main() {
  group('DbTask', () {
    late ExportTaskConfig exportConfig;
    late DbTask task;

    setUp(() {
      exportConfig = ExportTaskConfig(
        connectionId: 'conn_1',
        databaseName: 'test_db',
        description: 'Export users table',
        tableName: 'users',
        outputPath: '/tmp/users.csv',
        format: ExportFormat.csv,
      );

      task = DbTask(
        id: 'task_001',
        type: TaskType.export,
        config: exportConfig,
      );
    });

    test('initial state is pending', () {
      expect(task.status, equals(TaskStatus.pending));
      expect(task.progress, equals(0));
      expect(task.isActive, isTrue);
      expect(task.isDone, isFalse);
    });

    test('status transitions update isActive and isDone', () {
      task.status = TaskStatus.running;
      expect(task.isActive, isTrue);
      expect(task.isDone, isFalse);

      task.status = TaskStatus.completed;
      expect(task.isActive, isFalse);
      expect(task.isDone, isTrue);

      task.status = TaskStatus.failed;
      expect(task.isActive, isFalse);
      expect(task.isDone, isTrue);

      task.status = TaskStatus.cancelled;
      expect(task.isActive, isFalse);
      expect(task.isDone, isTrue);

      task.status = TaskStatus.paused;
      expect(task.isActive, isTrue);
      expect(task.isDone, isFalse);
    });

    test('cancel sets isCancelled', () {
      expect(task.isCancelled, isFalse);
      task.cancel();
      expect(task.isCancelled, isTrue);
    });

    test('reset clears isCancelled', () {
      task.cancel();
      expect(task.isCancelled, isTrue);
      task.reset();
      expect(task.isCancelled, isFalse);
    });

    test('progressPercent calculates correctly', () {
      expect(task.progressPercent, isNull);

      task.totalRows = 100;
      task.processedRows = 25;
      expect(task.progressPercent, equals(25.0));

      task.processedRows = 50;
      expect(task.progressPercent, equals(50.0));

      task.processedRows = 150;
      expect(task.progressPercent, equals(100.0));
    });

    test('progressPercent clamps to 0-100', () {
      task.totalRows = 100;
      task.processedRows = -10;
      expect(task.progressPercent, equals(0.0));

      task.processedRows = 200;
      expect(task.progressPercent, equals(100.0));
    });

    test('duration returns null when not started', () {
      expect(task.duration, isNull);
    });

    test('duration calculates correctly when running', () {
      final now = DateTime.now();
      task.startedAt = now.subtract(const Duration(seconds: 30));
      final duration = task.duration;
      expect(duration, isNotNull);
      expect(duration!.inSeconds, closeTo(30, 2));
    });

    test('duration uses completedAt when available', () {
      final now = DateTime.now();
      task.startedAt = now.subtract(const Duration(minutes: 5));
      task.completedAt = now.subtract(const Duration(minutes: 2));
      final duration = task.duration;
      expect(duration!.inMinutes, closeTo(3, 1));
    });

    test('addLog appends to logs list', () {
      expect(task.logs, isEmpty);
      task.addInfo('Starting export');
      expect(task.logs.length, equals(1));
      expect(task.logs.first.message, equals('Starting export'));
      expect(task.logs.first.level, equals(LogLevel.info));
    });

    test('addWarning creates warning log', () {
      task.addWarning('Low memory');
      expect(task.logs.first.level, equals(LogLevel.warning));
    });

    test('addError creates error log', () {
      task.addError('Connection lost');
      expect(task.logs.first.level, equals(LogLevel.error));
    });

    test('addSuccess creates success log', () {
      task.addSuccess('Export complete');
      expect(task.logs.first.level, equals(LogLevel.success));
    });

    test('displayName returns config description', () {
      expect(task.displayName, equals('Export users table'));
    });

    test('typeLabel returns correct labels', () {
      expect(task.typeLabel, equals('导出'));

      final importTask = DbTask(
        id: 'task_002',
        type: TaskType.import,
        config: exportConfig,
      );
      expect(importTask.typeLabel, equals('导入'));

      final queryTask = DbTask(
        id: 'task_003',
        type: TaskType.query,
        config: exportConfig,
      );
      expect(queryTask.typeLabel, equals('查询'));
    });

    test('typeIcon returns correct icons', () {
      expect(task.typeIcon, equals(LucideIcons.fileDown));

      final importTask = DbTask(
        id: 'task_002',
        type: TaskType.import,
        config: exportConfig,
      );
      expect(importTask.typeIcon, equals(LucideIcons.fileUp));

      final queryTask = DbTask(
        id: 'task_003',
        type: TaskType.query,
        config: exportConfig,
      );
      expect(queryTask.typeIcon, equals(LucideIcons.search));
    });

    test('statusColor returns correct colors', () {
      task.status = TaskStatus.pending;
      expect(task.statusColor, equals(Colors.grey));

      task.status = TaskStatus.running;
      expect(task.statusColor, equals(Colors.blue));

      task.status = TaskStatus.paused;
      expect(task.statusColor, equals(Colors.orange));

      task.status = TaskStatus.completed;
      expect(task.statusColor, equals(Colors.green));

      task.status = TaskStatus.failed;
      expect(task.statusColor, equals(Colors.red));
    });

    test('statusLabel returns correct labels', () {
      task.status = TaskStatus.pending;
      expect(task.statusLabel, equals('等待中'));

      task.status = TaskStatus.running;
      expect(task.statusLabel, equals('执行中'));

      task.status = TaskStatus.paused;
      expect(task.statusLabel, equals('已暂停'));

      task.status = TaskStatus.completed;
      expect(task.statusLabel, equals('已完成'));

      task.status = TaskStatus.failed;
      expect(task.statusLabel, equals('失败'));

      task.status = TaskStatus.cancelled;
      expect(task.statusLabel, equals('已取消'));
    });

    test('toJson serializes correctly', () {
      task.status = TaskStatus.running;
      task.progress = 50;
      task.totalRows = 1000;
      task.processedRows = 500;
      task.addInfo('Test log');

      final json = task.toJson();
      expect(json['id'], equals('task_001'));
      expect(json['type'], equals('export'));
      expect(json['status'], equals('running'));
      expect(json['progress'], equals(50));
      expect(json['totalRows'], equals(1000));
      expect(json['processedRows'], equals(500));
      expect(json['logs'], isA<List>());
      expect((json['logs'] as List).length, equals(1));
    });
  });

  group('TaskConfig', () {
    test('ExportTaskConfig serializes correctly', () {
      final config = ExportTaskConfig(
        connectionId: 'conn_1',
        databaseName: 'test_db',
        description: 'Export users',
        tableName: 'users',
        outputPath: '/tmp/users.csv',
        format: ExportFormat.csv,
        whereClause: 'id > 100',
        limit: 1000,
        includeHeader: true,
        encoding: 'utf-8',
      );

      final json = config.toJson();
      expect(json['type'], equals('export'));
      expect(json['tableName'], equals('users'));
      expect(json['format'], equals('csv'));
      expect(json['whereClause'], equals('id > 100'));
      expect(json['limit'], equals(1000));
      expect(json['includeHeader'], isTrue);
    });

    test('ImportTaskConfig serializes correctly', () {
      final config = ImportTaskConfig(
        connectionId: 'conn_1',
        description: 'Import data',
        filePath: '/tmp/data.csv',
        targetTable: 'users',
        format: ImportFormat.csv,
        hasHeader: true,
        delimiter: ',',
        createTableIfNotExists: true,
        createTableSQL: 'CREATE TABLE users (id INT)',
      );

      final json = config.toJson();
      expect(json['type'], equals('import'));
      expect(json['filePath'], equals('/tmp/data.csv'));
      expect(json['targetTable'], equals('users'));
      expect(json['format'], equals('csv'));
      expect(json['hasHeader'], isTrue);
      expect(json['delimiter'], equals(','));
      expect(json['createTableIfNotExists'], isTrue);
    });

    test('QueryTaskConfig serializes correctly', () {
      final config = QueryTaskConfig(
        connectionId: 'conn_1',
        description: 'Run report',
        sql: 'SELECT * FROM users',
        saveToFile: true,
        outputPath: '/tmp/report.csv',
        outputFormat: ExportFormat.csv,
      );

      final json = config.toJson();
      expect(json['type'], equals('query'));
      expect(json['sql'], equals('SELECT * FROM users'));
      expect(json['saveToFile'], isTrue);
      expect(json['outputPath'], equals('/tmp/report.csv'));
      expect(json['outputFormat'], equals('csv'));
    });
  });

  group('TaskLog', () {
    test('factory constructors create correct levels', () {
      final info = TaskLog.info('Info message');
      expect(info.level, equals(LogLevel.info));

      final warning = TaskLog.warning('Warning message');
      expect(warning.level, equals(LogLevel.warning));

      final error = TaskLog.error('Error message');
      expect(error.level, equals(LogLevel.error));

      final success = TaskLog.success('Success message');
      expect(success.level, equals(LogLevel.success));
    });

    test('timestamp is set automatically', () {
      final before = DateTime.now();
      final log = TaskLog.info('Test');
      final after = DateTime.now();

      expect(
        log.timestamp.isAfter(before) || log.timestamp.isAtSameMomentAs(before),
        isTrue,
      );
      expect(
        log.timestamp.isBefore(after) || log.timestamp.isAtSameMomentAs(after),
        isTrue,
      );
    });
  });
}
