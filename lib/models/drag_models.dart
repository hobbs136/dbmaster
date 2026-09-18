/// Data transferred during table drag-and-drop operations
class TableDragData {
  final String tableName;
  final String databaseName;
  final String connectionId;

  TableDragData({
    required this.tableName,
    required this.databaseName,
    required this.connectionId,
  });

  /// Use double-quote escaping as a database-agnostic fallback.
  /// Callers SHOULD prefer [DatabaseAdapter.getDefaultBrowseQuery] for
  /// database-specific identifier quoting.
  String get selectStatement => 'SELECT * FROM "$tableName" LIMIT 100';
}
