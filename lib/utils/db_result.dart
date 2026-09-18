/// 统一的结果类型，替代直接抛出异常或返回 null
///
/// 使用方式：
///   `Future<Result<List<Map<String, dynamic>>>> executeQuery(String sql)`
///   final result = await dbService.executeQuery(sql);
///   if (result.isFailure) {
///     handleError(result.error!);
///   } else {
///     processData(result.data!);
///   }
///
/// 或者用模式匹配：
///   final result = await dbService.executeQuery(sql);
///   result.fold(
///     onSuccess: (data) => AppLogger.d('DbResult', 'Got ${data.length} rows'),
///     onFailure: (error) => AppLogger.d('DbResult', 'Error: $error'),
///   );
sealed class Result<T> {
  const Result();

  bool get isSuccess => this is Success<T>;
  bool get isFailure => this is Failure<T>;

  T? get data => this is Success<T> ? (this as Success<T>).data : null;
  DbQueryError? get error =>
      this is Failure<T> ? (this as Failure<T>).error : null;

  R fold<R>({
    required R Function(T data) onSuccess,
    required R Function(DbQueryError error) onFailure,
  }) {
    return switch (this) {
      Success<T>(:final data) => onSuccess(data),
      Failure<T>(:final error) => onFailure(error),
    };
  }

  /// 转换成功值的类型
  Result<R> map<R>(R Function(T data) transform) {
    return switch (this) {
      Success<T>(:final data) => Success(transform(data)),
      Failure<T>(:final error) => Failure(error),
    };
  }

  /// 取值，带默认值
  T getOrElse(T defaultValue) => data ?? defaultValue;

  /// 取值，null 则抛异常
  T getOrThrow() =>
      data ?? (throw Exception(error?.message ?? 'Unknown error'));
}

class Success<T> extends Result<T> {
  @override
  final T data;
  const Success(this.data);
}

class Failure<T> extends Result<T> {
  @override
  final DbQueryError error;
  const Failure(this.error);
}

/// 数据库查询错误类型
/// 替代所有散落的字符串错误信息
enum DbQueryErrorType {
  /// 连接失败（网络、认证、拒绝等）
  connectionFailed('连接失败'),

  /// 连接超时
  connectionTimeout('连接超时'),

  /// 查询执行失败（语法错误、约束违反等）
  queryFailed('查询执行失败'),

  /// 查询被用户取消
  queryCancelled('查询已取消'),

  /// 查询超时
  queryTimeout('查询超时'),

  /// 权限不足
  permissionDenied('权限不足'),

  /// 数据库不存在
  databaseNotFound('数据库不存在'),

  /// 表不存在
  tableNotFound('表不存在'),

  /// 字段不存在
  columnNotFound('字段不存在'),

  /// 危险操作被拦截（如裸 DELETE）
  dangerousOperation('危险操作'),

  /// 未知错误
  unknown('未知错误');

  final String label;
  const DbQueryErrorType(this.label);
}

class DbQueryError {
  final DbQueryErrorType type;
  final String message;
  final String? sql;
  final Object? originalError;
  final StackTrace? stackTrace;

  const DbQueryError({
    required this.type,
    required this.message,
    this.sql,
    this.originalError,
    this.stackTrace,
  });

  factory DbQueryError.connectionFailed(String detail, [Object? e]) =>
      DbQueryError(
        type: DbQueryErrorType.connectionFailed,
        message: '连接失败: $detail',
        originalError: e,
      );

  factory DbQueryError.connectionTimeout() => const DbQueryError(
    type: DbQueryErrorType.connectionTimeout,
    message: '连接超时，请检查网络或服务器状态',
  );

  factory DbQueryError.queryFailed(String sql, String detail, [Object? e]) =>
      DbQueryError(
        type: DbQueryErrorType.queryFailed,
        message: '查询执行失败: $detail',
        sql: sql,
        originalError: e,
      );

  factory DbQueryError.queryCancelled() => const DbQueryError(
    type: DbQueryErrorType.queryCancelled,
    message: '查询已被取消',
  );

  factory DbQueryError.queryTimeout(int seconds) => DbQueryError(
    type: DbQueryErrorType.queryTimeout,
    message: '查询超时（$seconds秒），请优化查询或增加超时时间',
  );

  factory DbQueryError.permissionDenied(String detail) => DbQueryError(
    type: DbQueryErrorType.permissionDenied,
    message: '权限不足: $detail',
  );

  factory DbQueryError.dangerousOperation(String sql) => DbQueryError(
    type: DbQueryErrorType.dangerousOperation,
    message: '危险操作已拦截，请确认操作意图',
    sql: sql,
  );

  factory DbQueryError.tableNotFound(String table) => DbQueryError(
    type: DbQueryErrorType.tableNotFound,
    message: '表不存在: $table',
  );

  factory DbQueryError.databaseNotFound(String db) => DbQueryError(
    type: DbQueryErrorType.databaseNotFound,
    message: '数据库不存在: $db',
  );

  factory DbQueryError.unknown([String? detail, Object? e, StackTrace? st]) =>
      DbQueryError(
        type: DbQueryErrorType.unknown,
        message: detail ?? '发生未知错误',
        originalError: e,
        stackTrace: st,
      );

  @override
  String toString() => '[${type.label}] $message';
}
