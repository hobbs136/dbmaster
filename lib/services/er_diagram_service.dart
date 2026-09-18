import 'dart:ui' as ui;
import '../models/er_diagram.dart';
import 'database_abstract.dart';
import 'database_service.dart';
import '../utils/app_logger.dart';

class ERDiagramService {
  final DatabaseService _dbService;

  ERDiagramService(this._dbService);

  Future<ERDiagram> buildERDiagram() async {
    if (!_dbService.isConnected) {
      throw Exception('Not connected to database');
    }

    try {
      final nodes = await getTableNodes();
      final edges = await getRelationships(nodes);
      return ERDiagram(nodes: nodes, edges: edges);
    } catch (e) {
      AppLogger.d('ERDiagram', 'DEBUG: buildERDiagram error: $e');
      rethrow;
    }
  }

  // T29：MySQL 族已迁网关壳——经当前连接的 adapter 执行（原裸
  // MySQLConnection 通道下线）。行取值按列序位置（网关行是列名 map，
  // 保持插入序）。
  static String? _colAt(Map<String, dynamic> row, int i) {
    final values = row.values.toList();
    return i < values.length ? values[i]?.toString() : null;
  }

  Future<List<ERNode>> getTableNodes() async {
    if (!_dbService.isConnected) {
      throw Exception('Not connected to database');
    }

    final adapter = _dbService.currentAdapter;
    if (adapter == null || !adapter.isConnected) {
      throw Exception('Connection lost');
    }

    try {
      final tableNames = await _dbService.getTables();
      final nodes = <ERNode>[];
      const batchSize = 20;
      final total = tableNames.length;

      for (var i = 0; i < tableNames.length; i += batchSize) {
        final batch = tableNames.skip(i).take(batchSize).toList();
        final futures = batch.map(
          (tableName) => _processTable(adapter, tableName),
        );
        final batchResults = await Future.wait(futures);

        for (final result in batchResults) {
          if (result != null) {
            nodes.add(result);
          }
        }

        final progress = (i + batch.length).clamp(0, total);
        AppLogger.d('ERDiagram', 'DEBUG: Processed $progress/$total tables');
      }

      return nodes;
    } catch (e) {
      AppLogger.d('ERDiagram', 'DEBUG: getTableNodes error: $e');
      rethrow;
    }
  }

  Future<ERNode?> _processTable(
    DatabaseAdapter adapter,
    String tableName,
  ) async {
    try {
      final primaryKeys = await _getPrimaryKeys(tableName);
      final foreignKeys = await getForeignKeys(tableName);
      final columns = await _dbService.getTableColumns(tableName);

      int rowCount = 0;
      try {
        final countResult = await adapter.executeQuery(
          'SELECT COUNT(*) as cnt FROM `$tableName`',
        );
        if (countResult.rows.isNotEmpty) {
          rowCount = int.tryParse(
                countResult.rows.first['cnt']?.toString() ?? '',
              ) ??
              0;
        }
      } catch (e) {
        // Ignore row count errors for individual tables
      }

      final height = 40.0 + (columns.length * 24.0);
      const width = 200.0;

      return ERNode(
        tableName: tableName,
        primaryKeys: primaryKeys,
        foreignKeys: foreignKeys,
        columns: columns.map((col) => col.name).toList(),
        rowCount: rowCount,
        size: ui.Size(width, height),
      );
    } catch (e) {
      AppLogger.d('ERDiagram', 'DEBUG: Error processing table $tableName: $e');
      return null;
    }
  }

  /// Get all foreign keys for a specific table
  Future<List<ForeignKey>> getForeignKeys(String tableName) async {
    final adapter = _dbService.currentAdapter;
    if (adapter == null || !adapter.isConnected) {
      return [];
    }

    try {
      // Query information_schema for foreign keys
      final results = await adapter.executeQuery('''
        SELECT
          CONSTRAINT_NAME as name,
          TABLE_NAME as table_name,
          COLUMN_NAME as column_name,
          REFERENCED_TABLE_NAME as ref_table,
          REFERENCED_COLUMN_NAME as ref_column,
          UPDATE_RULE as on_update,
          DELETE_RULE as on_delete
        FROM information_schema.KEY_COLUMN_USAGE
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = '${tableName.replaceAll("'", "''")}'
          AND REFERENCED_TABLE_NAME IS NOT NULL
        ORDER BY CONSTRAINT_NAME, ORDINAL_POSITION
      ''');

      final foreignKeys = <ForeignKey>[];

      for (final row in results.rows) {
        foreignKeys.add(
          ForeignKey(
            name: _colAt(row, 0) ?? '',
            table: _colAt(row, 1) ?? '',
            column: _colAt(row, 2) ?? '',
            referencedTable: _colAt(row, 3) ?? '',
            referencedColumn: _colAt(row, 4) ?? '',
            onUpdate: _colAt(row, 5),
            onDelete: _colAt(row, 6),
          ),
        );
      }

      return foreignKeys;
    } catch (e) {
      AppLogger.d(
        'ERDiagram',
        'DEBUG: getForeignKeys error for $tableName: $e',
      );
      return [];
    }
  }

  /// Get all relationships (edges) between tables
  Future<List<EREdge>> getRelationships(List<ERNode> nodes) async {
    final edges = <EREdge>[];

    // Create a map for quick node lookup
    final nodeMap = {for (var node in nodes) node.tableName: node};

    for (final node in nodes) {
      for (final fk in node.foreignKeys) {
        // Find the referenced node
        final referencedNode = nodeMap[fk.referencedTable];

        if (referencedNode != null) {
          // Create field mapping
          final fieldMapping = FieldMapping(
            fromField: fk.column,
            toField: fk.referencedColumn,
          );

          // Check if edge already exists (multi-column foreign key)
          final existingEdge = edges.firstWhere(
            (edge) =>
                edge.name == fk.name &&
                edge.fromNode.tableName == node.tableName &&
                edge.toNode.tableName == fk.referencedTable,
            orElse: () => EREdge(
              name: fk.name,
              fromNode: node,
              toNode: referencedNode,
              fieldMappings: [],
              onUpdate: fk.onUpdate,
              onDelete: fk.onDelete,
            ),
          );

          // Add field mapping to existing or new edge
          if (edges.contains(existingEdge)) {
            existingEdge.fieldMappings.add(fieldMapping);
          } else {
            existingEdge.fieldMappings.add(fieldMapping);
            edges.add(existingEdge);
          }
        }
      }
    }

    return edges;
  }

  /// Get primary keys for a table
  Future<List<String>> _getPrimaryKeys(String tableName) async {
    final adapter = _dbService.currentAdapter;
    if (adapter == null || !adapter.isConnected) {
      return [];
    }

    try {
      final results = await adapter.executeQuery('''
        SELECT COLUMN_NAME
        FROM information_schema.KEY_COLUMN_USAGE
        WHERE TABLE_SCHEMA = DATABASE()
          AND TABLE_NAME = '${tableName.replaceAll("'", "''")}'
          AND CONSTRAINT_NAME = 'PRIMARY'
        ORDER BY ORDINAL_POSITION
      ''');

      final primaryKeys = <String>[];
      for (final row in results.rows) {
        primaryKeys.add(_colAt(row, 0) ?? '');
      }

      return primaryKeys;
    } catch (e) {
      AppLogger.d(
        'ERDiagram',
        'DEBUG: _getPrimaryKeys error for $tableName: $e',
      );
      return [];
    }
  }

  /// Search nodes by table name
  List<ERNode> searchNodes(List<ERNode> nodes, String query) {
    if (query.isEmpty) return nodes;

    final lowerQuery = query.toLowerCase();
    return nodes.where((node) {
      return node.tableName.toLowerCase().contains(lowerQuery);
    }).toList();
  }

  /// Search edges by relationship
  List<EREdge> searchEdges(List<EREdge> edges, String query) {
    if (query.isEmpty) return edges;

    final lowerQuery = query.toLowerCase();
    return edges.where((edge) {
      return edge.name.toLowerCase().contains(lowerQuery) ||
          edge.fromNode.tableName.toLowerCase().contains(lowerQuery) ||
          edge.toNode.tableName.toLowerCase().contains(lowerQuery);
    }).toList();
  }

  /// Filter nodes to show only connected or isolated tables
  List<ERNode> filterNodesByConnectivity(
    List<ERNode> nodes,
    bool showIsolated,
  ) {
    if (showIsolated) return nodes;
    return nodes.where((node) => !node.isIsolated).toList();
  }

  /// Get detailed information about a table
  Future<Map<String, dynamic>> getTableDetails(String tableName) async {
    final adapter = _dbService.currentAdapter;
    if (adapter == null || !adapter.isConnected) {
      throw Exception('Connection lost');
    }

    try {
      // Get table structure
      final columns = await _dbService.getTableColumns(tableName);

      // Get indexes
      final indexes = await _dbService.getTableIndexes(tableName);

      // Get foreign keys
      final foreignKeys = await getForeignKeys(tableName);

      // Get primary keys
      final primaryKeys = await _getPrimaryKeys(tableName);

      // Get table properties
      final properties = await _dbService.getTableProperties(tableName);

      // Get CREATE TABLE statement
      final createSql = await _dbService.getCreateTableSql(tableName);

      // Get row count
      final rowCount = await _dbService.getTableRowCount(tableName);

      return {
        'tableName': tableName,
        'columns': columns
            .map(
              (col) => {
                'name': col.name,
                'type': col.type,
                'isPrimaryKey': col.isPrimaryKey,
                'isNullable': col.isNullable,
                'defaultValue': col.defaultValue,
              },
            )
            .toList(),
        'indexes': indexes
            .map(
              (idx) => {
                'name': idx.name,
                'columns': idx.columns,
                'isUnique': idx.isUnique,
              },
            )
            .toList(),
        'foreignKeys': foreignKeys.map((fk) => fk.toJson()).toList(),
        'primaryKeys': primaryKeys,
        'properties': properties,
        'createSql': createSql,
        'rowCount': rowCount,
      };
    } catch (e) {
      AppLogger.d(
        'ERDiagram',
        'DEBUG: getTableDetails error for $tableName: $e',
      );
      rethrow;
    }
  }
}
