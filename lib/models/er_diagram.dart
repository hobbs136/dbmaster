import 'package:flutter/material.dart';
import 'database_models.dart' show ForeignKey;
export 'database_models.dart' show ForeignKey;

/// Represents a field mapping in a relationship
class FieldMapping {
  final String fromField;
  final String toField;

  FieldMapping({required this.fromField, required this.toField});

  Map<String, dynamic> toJson() {
    return {'fromField': fromField, 'toField': toField};
  }

  factory FieldMapping.fromJson(Map<String, dynamic> json) {
    return FieldMapping(
      fromField: json['fromField'] as String,
      toField: json['toField'] as String,
    );
  }
}

/// Represents a table node in the ER diagram
class ERNode {
  final String tableName;
  final List<String> primaryKeys;
  final List<ForeignKey> foreignKeys;
  final List<String> columns;
  final int rowCount;
  Offset position;
  Size size;

  ERNode({
    required this.tableName,
    required this.primaryKeys,
    required this.foreignKeys,
    required this.columns,
    required this.rowCount,
    this.position = Offset.zero,
    this.size = const Size(200, 150),
  });

  bool get isIsolated => foreignKeys.isEmpty;

  ERNode copyWith({
    String? tableName,
    List<String>? primaryKeys,
    List<ForeignKey>? foreignKeys,
    List<String>? columns,
    int? rowCount,
    Offset? position,
    Size? size,
  }) {
    return ERNode(
      tableName: tableName ?? this.tableName,
      primaryKeys: primaryKeys ?? this.primaryKeys,
      foreignKeys: foreignKeys ?? this.foreignKeys,
      columns: columns ?? this.columns,
      rowCount: rowCount ?? this.rowCount,
      position: position ?? this.position,
      size: size ?? this.size,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'tableName': tableName,
      'primaryKeys': primaryKeys,
      'foreignKeys': foreignKeys.map((fk) => fk.toJson()).toList(),
      'columns': columns,
      'rowCount': rowCount,
      'position': {'dx': position.dx, 'dy': position.dy},
      'size': {'width': size.width, 'height': size.height},
    };
  }

  factory ERNode.fromJson(Map<String, dynamic> json) {
    final pos = json['position'] as Map<String, dynamic>;
    final sz = json['size'] as Map<String, dynamic>;
    return ERNode(
      tableName: json['tableName'] as String,
      primaryKeys: List<String>.from(json['primaryKeys']),
      foreignKeys: (json['foreignKeys'] as List)
          .map((fk) => ForeignKey.fromJson(fk as Map<String, dynamic>))
          .toList(),
      columns: List<String>.from(json['columns']),
      rowCount: json['rowCount'] as int,
      position: Offset(pos['dx'] as double, pos['dy'] as double),
      size: Size(sz['width'] as double, sz['height'] as double),
    );
  }

  @override
  String toString() {
    return 'ERNode($tableName, ${columns.length} cols, ${foreignKeys.length} fks)';
  }
}

/// Represents a relationship edge between two nodes in the ER diagram
class EREdge {
  final String name;
  final ERNode fromNode;
  final ERNode toNode;
  final List<FieldMapping> fieldMappings;
  final String? onUpdate;
  final String? onDelete;

  EREdge({
    required this.name,
    required this.fromNode,
    required this.toNode,
    required this.fieldMappings,
    this.onUpdate,
    this.onDelete,
  });

  bool get isOneToMany => true; // Default assumption for foreign keys
  bool get isManyToMany => false; // Would need junction table detection

  EREdge copyWith({
    String? name,
    ERNode? fromNode,
    ERNode? toNode,
    List<FieldMapping>? fieldMappings,
    String? onUpdate,
    String? onDelete,
  }) {
    return EREdge(
      name: name ?? this.name,
      fromNode: fromNode ?? this.fromNode,
      toNode: toNode ?? this.toNode,
      fieldMappings: fieldMappings ?? this.fieldMappings,
      onUpdate: onUpdate ?? this.onUpdate,
      onDelete: onDelete ?? this.onDelete,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'fromNode': fromNode.tableName,
      'toNode': toNode.tableName,
      'fieldMappings': fieldMappings.map((fm) => fm.toJson()).toList(),
      'onUpdate': onUpdate,
      'onDelete': onDelete,
    };
  }

  @override
  String toString() {
    return 'EREdge($name: ${fromNode.tableName} -> ${toNode.tableName})';
  }

  factory EREdge.fromJson(Map<String, dynamic> json, List<ERNode> allNodes) {
    final fromTableName = json['fromNode'] as String;
    final toTableName = json['toNode'] as String;

    final fromNode = allNodes.firstWhere(
      (node) => node.tableName == fromTableName,
      orElse: () => throw Exception('Node not found: $fromTableName'),
    );

    final toNode = allNodes.firstWhere(
      (node) => node.tableName == toTableName,
      orElse: () => throw Exception('Node not found: $toTableName'),
    );

    return EREdge(
      name: json['name'] as String,
      fromNode: fromNode,
      toNode: toNode,
      fieldMappings: (json['fieldMappings'] as List)
          .map((fm) => FieldMapping.fromJson(fm as Map<String, dynamic>))
          .toList(),
      onUpdate: json['onUpdate'] as String?,
      onDelete: json['onDelete'] as String?,
    );
  }
}

/// Represents the complete ER diagram
class ERDiagram {
  final List<ERNode> nodes;
  final List<EREdge> edges;
  final DateTime createdAt;

  ERDiagram({required this.nodes, required this.edges, DateTime? createdAt})
    : createdAt = createdAt ?? DateTime.now();

  List<ERNode> get isolatedNodes =>
      nodes.where((node) => node.isIsolated).toList();
  List<ERNode> get connectedNodes =>
      nodes.where((node) => !node.isIsolated).toList();
  int get tableCount => nodes.length;
  int get relationshipCount => edges.length;

  ERDiagram copyWith({
    List<ERNode>? nodes,
    List<EREdge>? edges,
    DateTime? createdAt,
  }) {
    return ERDiagram(
      nodes: nodes ?? this.nodes,
      edges: edges ?? this.edges,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'nodes': nodes.map((node) => node.toJson()).toList(),
      'edges': edges.map((edge) => edge.toJson()).toList(),
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory ERDiagram.fromJson(Map<String, dynamic> json) {
    final nodeList = (json['nodes'] as List)
        .map((node) => ERNode.fromJson(node as Map<String, dynamic>))
        .toList();

    final edgeList = (json['edges'] as List)
        .map((edge) => EREdge.fromJson(edge as Map<String, dynamic>, nodeList))
        .toList();

    return ERDiagram(
      nodes: nodeList,
      edges: edgeList,
      createdAt: json['createdAt'] != null
          ? DateTime.parse(json['createdAt'] as String)
          : DateTime.now(),
    );
  }

  @override
  String toString() {
    return 'ERDiagram($tableCount tables, $relationshipCount relationships)';
  }
}
