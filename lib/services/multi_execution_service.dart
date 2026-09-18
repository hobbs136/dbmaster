import 'dart:async';
import '../models/sql_statement.dart';
import '../models/execution_result.dart';
import '../models/dml_risk_models.dart';
import 'readonly_guard.dart';
import 'database_service.dart';

/// Execution status enumeration
enum ExecutionStatus { idle, executing, completed, cancelled }

/// Progress information for multi-execution
class ExecutionProgress {
  final int currentIndex;
  final int totalCount;
  final SQLStatement? currentStatement;
  final ExecutionStatus status;
  final Duration elapsedTime;
  final ExecutionResult? lastResult;

  const ExecutionProgress({
    required this.currentIndex,
    required this.totalCount,
    this.currentStatement,
    required this.status,
    required this.elapsedTime,
    this.lastResult,
  });

  double get percentComplete =>
      totalCount > 0 ? (currentIndex / totalCount) * 100 : 0;
  bool get isComplete => currentIndex >= totalCount;

  ExecutionProgress copyWith({
    int? currentIndex,
    int? totalCount,
    SQLStatement? currentStatement,
    ExecutionStatus? status,
    Duration? elapsedTime,
    ExecutionResult? lastResult,
  }) {
    return ExecutionProgress(
      currentIndex: currentIndex ?? this.currentIndex,
      totalCount: totalCount ?? this.totalCount,
      currentStatement: currentStatement ?? this.currentStatement,
      status: status ?? this.status,
      elapsedTime: elapsedTime ?? this.elapsedTime,
      lastResult: lastResult ?? this.lastResult,
    );
  }
}

/// Function type for executing SQL queries
/// Used for dependency injection in tests
typedef QueryExecutor = Future<List<Map<String, dynamic>>> Function(String sql);

/// Service for executing multiple SQL statements sequentially with progress tracking
class MultiExecutionService {
  final DatabaseService? _databaseService;
  final QueryExecutor? _customExecutor;
  final _progressController = StreamController<ExecutionProgress>.broadcast();

  bool _isExecuting = false;
  bool _isCancelled = false;

  Stream<ExecutionProgress> get progressStream => _progressController.stream;
  bool get isExecuting => _isExecuting;

  final String? _connectionId;
  final String? _database;
  final String? _sessionId;

  /// Creates a service using the default DatabaseService
  MultiExecutionService(
    DatabaseService databaseService, {
    String? connectionId,
    String? database,
    String? sessionId,
  }) : _databaseService = databaseService,
       _customExecutor = null,
       _connectionId = connectionId,
       _database = database,
       _sessionId = sessionId;

  /// Creates a service with a custom query executor (for testing)
  MultiExecutionService.withExecutor(QueryExecutor executor)
    : _databaseService = null,
      _customExecutor = executor,
      _connectionId = null,
      _database = null,
      _sessionId = null;

  /// Execute multiple SQL statements sequentially
  ///
  /// Returns a list of execution results, one for each statement.
  /// If a statement fails, execution continues with the next statement.
  /// Use [cancel()] to stop execution early.
  /// [onProgress]：逐条执行进度回调（与 progressStream 同源；供 UI 展示
  /// 「n/total」计数，避免长脚本执行期间无反馈被感知为卡死）。
  Future<List<ExecutionResult>> execute(List<SQLStatement> statements,
      {bool skipDdlAnalysis = false,
      void Function(ExecutionProgress progress)? onProgress}) async {
    if (_isExecuting) {
      throw StateError('Already executing statements');
    }

    if (statements.isEmpty) {
      return [];
    }

    _isExecuting = true;
    _isCancelled = false;
    final results = <ExecutionResult>[];
    final startTime = DateTime.now();
    ExecutionStatus finalStatus = ExecutionStatus.executing;

    // 多语句执行期间挂起逐条查询历史写入：每条 addQueryHistory 会
    // jsonEncode 全量历史 + SharedPreferences 平台通道写 + AppProvider
    // 全树 notify，×N 条为 O(n²)——462 条脚本实测 UI 线程阻塞 40s+（用户
    // 报告的「执行到后面卡死」）。整脚本汇总记录由调用方（app_provider
    // 的 addQueryHistory）在执行结束后写入一次。
    final interceptor = _databaseService?.interceptor;
    final wasHistoryRecording = interceptor?.enableHistoryRecording ?? false;
    interceptor?.enableHistoryRecording = false;

    try {
      for (int i = 0; i < statements.length; i++) {
        if (_isCancelled) {
          finalStatus = ExecutionStatus.cancelled;
          break;
        }

        final statement = statements[i];
        final elapsed = DateTime.now().difference(startTime);

        // Emit progress before execution
        _emitProgress(
          ExecutionProgress(
            currentIndex: i,
            totalCount: statements.length,
            currentStatement: statement,
            status: ExecutionStatus.executing,
            elapsedTime: elapsed,
          ),
        );

        final result = await _executeStatement(
          statement,
          skipDdlAnalysis: skipDdlAnalysis,
        );
        results.add(result);
        onProgress?.call(
          ExecutionProgress(
            currentIndex: i + 1,
            totalCount: statements.length,
            currentStatement: statement,
            status: ExecutionStatus.executing,
            elapsedTime: DateTime.now().difference(startTime),
            lastResult: result,
          ),
        );

        // Emit progress after execution
        _emitProgress(
          ExecutionProgress(
            currentIndex: i + 1,
            totalCount: statements.length,
            currentStatement: statement,
            status: ExecutionStatus.executing,
            elapsedTime: DateTime.now().difference(startTime),
            lastResult: result,
          ),
        );
      }

      final finalElapsed = DateTime.now().difference(startTime);

      // Determine final status
      if (_isCancelled) {
        finalStatus = ExecutionStatus.cancelled;
      } else if (results.length == statements.length) {
        finalStatus = ExecutionStatus.completed;
      }

      _emitProgress(
        ExecutionProgress(
          currentIndex: results.length,
          totalCount: statements.length,
          status: finalStatus,
          elapsedTime: finalElapsed,
        ),
      );

      // Give stream listeners time to process the final event
      await Future<void>.delayed(Duration.zero);

      return results;
    } finally {
      interceptor?.enableHistoryRecording = wasHistoryRecording;
      _isExecuting = false;
    }
  }

  void _emitProgress(ExecutionProgress progress) {
    if (!_progressController.isClosed) {
      _progressController.add(progress);
    }
  }

  /// Execute a single SQL statement
  Future<ExecutionResult> _executeStatement(
    SQLStatement statement, {
    bool skipDdlAnalysis = false,
  }) async {
    final startTime = DateTime.now();

    try {
      final List<Map<String, dynamic>> data;
      if (_customExecutor != null) {
        data = await _customExecutor(statement.sql);
      } else {
        data = await _databaseService!.executeQuery(
          statement.sql,
          connectionId: _connectionId,
          database: _database,
          sessionId: _sessionId,
          skipDdlAnalysis: skipDdlAnalysis,
        );
      }
      final executionTime = DateTime.now().difference(startTime);

      return ExecutionResult(
        statement: statement,
        success: true,
        data: data,
        executionTime: executionTime,
        // C12：结果形态随语句连接类型下行（自建执行器路径无标记 → sqlRows）。
        dataShape: _databaseService?.lastDataShape,
      );
    } on DdlConfirmationRequiredException {
      rethrow;
    } on DmlConfirmationRequiredException {
      rethrow;
    } on DmlWarningRequiredException {
      rethrow;
    } on ReadOnlyBlockedException {
      rethrow;
    } catch (e) {
      final executionTime = DateTime.now().difference(startTime);

      return ExecutionResult(
        statement: statement,
        success: false,
        errorMessage: e.toString(),
        executionTime: executionTime,
      );
    }
  }

  /// Cancel the current execution
  ///
  /// The execution will stop after the current statement completes.
  void cancel() {
    _isCancelled = true;
  }

  /// Dispose of resources
  void dispose() {
    _progressController.close();
  }
}
