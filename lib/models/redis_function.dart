/// Redis Function（Redis 7.0+）
class RedisFunctionInfo {
  final String name;
  final String? description;
  final List<String> flags;

  RedisFunctionInfo({
    required this.name,
    this.description,
    this.flags = const [],
  });
}

/// Redis Function Library（Redis 7.0+）
class RedisFunctionLibrary {
  final String name;
  final String engine;
  final List<RedisFunctionInfo> functions;

  /// #6 — Lua source body of the library. Populated only when fetched via
  /// `FUNCTION LIST WITHCODE` (default FUNCTION LIST returns metadata only).
  /// Null when the server didn't include source (older call or unsupported).
  final String? sourceCode;

  RedisFunctionLibrary({
    required this.name,
    required this.engine,
    required this.functions,
    this.sourceCode,
  });
}
