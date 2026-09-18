import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/models/er_diagram.dart';

void main() {
  group('FieldMapping', () {
    test('toJson/fromJson round-trip', () {
      final fm = FieldMapping(fromField: 'user_id', toField: 'id');
      expect(fm.fromField, 'user_id');
      expect(fm.toField, 'id');

      final restored = FieldMapping.fromJson(fm.toJson());
      expect(restored.fromField, 'user_id');
      expect(restored.toField, 'id');
    });
  });

  group('ERNode', () {
    test('toJson/fromJson round-trip', () {
      final node = ERNode(
        tableName: 'users',
        primaryKeys: ['id'],
        foreignKeys: [],
        columns: ['id', 'name', 'email'],
        rowCount: 100,
        position: const Offset(10, 20),
        size: const Size(250, 180),
      );
      final restored = ERNode.fromJson(node.toJson());
      expect(restored.tableName, 'users');
      expect(restored.primaryKeys, ['id']);
      expect(restored.rowCount, 100);
      expect(restored.position.dx, 10);
      expect(restored.position.dy, 20);
      expect(restored.size.width, 250);
      expect(restored.size.height, 180);
    });

    test('isIsolated is true when no foreign keys', () {
      final node = ERNode(
        tableName: 't',
        primaryKeys: [],
        foreignKeys: [],
        columns: [],
        rowCount: 0,
      );
      expect(node.isIsolated, true);
    });

    test('copyWith updates fields', () {
      final node = ERNode(
        tableName: 't',
        primaryKeys: [],
        foreignKeys: [],
        columns: [],
        rowCount: 0,
      );
      final copied = node.copyWith(tableName: 'new_t', rowCount: 50);
      expect(copied.tableName, 'new_t');
      expect(copied.rowCount, 50);
    });
  });

  group('EREdge', () {
    test('isOneToMany is always true (default)', () {
      final a = ERNode(
        tableName: 'a',
        primaryKeys: [],
        foreignKeys: [],
        columns: [],
        rowCount: 0,
      );
      final b = ERNode(
        tableName: 'b',
        primaryKeys: [],
        foreignKeys: [],
        columns: [],
        rowCount: 0,
      );
      final edge = EREdge(
        name: 'fk_a_b',
        fromNode: a,
        toNode: b,
        fieldMappings: [],
      );
      expect(edge.isOneToMany, true);
      expect(edge.isManyToMany, false);
    });

    test('toJson uses table names for nodes', () {
      final a = ERNode(
        tableName: 'users',
        primaryKeys: [],
        foreignKeys: [],
        columns: [],
        rowCount: 0,
      );
      final b = ERNode(
        tableName: 'orders',
        primaryKeys: [],
        foreignKeys: [],
        columns: [],
        rowCount: 0,
      );
      final edge = EREdge(
        name: 'fk_users_orders',
        fromNode: a,
        toNode: b,
        fieldMappings: [FieldMapping(fromField: 'user_id', toField: 'id')],
        onUpdate: 'CASCADE',
        onDelete: 'SET NULL',
      );
      final json = edge.toJson();
      expect(json['name'], 'fk_users_orders');
      expect(json['fromNode'], 'users');
      expect(json['toNode'], 'orders');
      expect(json['onUpdate'], 'CASCADE');
      expect(json['onDelete'], 'SET NULL');
      expect((json['fieldMappings'] as List).length, 1);
    });

    test('fromJson reconstructs with node references', () {
      final users = ERNode(
        tableName: 'users',
        primaryKeys: ['id'],
        foreignKeys: [],
        columns: ['id', 'name'],
        rowCount: 10,
      );
      final orders = ERNode(
        tableName: 'orders',
        primaryKeys: ['order_id'],
        foreignKeys: [],
        columns: ['order_id', 'user_id'],
        rowCount: 50,
      );
      final allNodes = [users, orders];

      final edge = EREdge(
        name: 'fk_orders_users',
        fromNode: orders,
        toNode: users,
        fieldMappings: [FieldMapping(fromField: 'user_id', toField: 'id')],
      );

      final restored = EREdge.fromJson(edge.toJson(), allNodes);
      expect(restored.name, 'fk_orders_users');
      expect(restored.fromNode.tableName, 'orders');
      expect(restored.toNode.tableName, 'users');
    });

    test('fromJson throws when node not found', () {
      final users = ERNode(
        tableName: 'users',
        primaryKeys: [],
        foreignKeys: [],
        columns: [],
        rowCount: 0,
      );
      final orders = ERNode(
        tableName: 'orders',
        primaryKeys: [],
        foreignKeys: [],
        columns: [],
        rowCount: 0,
      );
      final edge = EREdge(
        name: 'fk',
        fromNode: orders,
        toNode: users,
        fieldMappings: [],
      );
      expect(
        () => EREdge.fromJson(edge.toJson(), [users]), // missing 'orders'
        throwsException,
      );
    });
  });

  group('ERDiagram', () {
    test('createdAt defaults to now', () {
      final diag = ERDiagram(nodes: [], edges: []);
      expect(
        diag.createdAt.isBefore(DateTime.now().add(const Duration(seconds: 1))),
        true,
      );
    });

    test('toJson/fromJson round-trip', () {
      final node = ERNode(
        tableName: 'users',
        primaryKeys: ['id'],
        foreignKeys: [],
        columns: ['id', 'name'],
        rowCount: 100,
      );
      final diag = ERDiagram(
        nodes: [node],
        edges: [],
        createdAt: DateTime(2026, 6, 1),
      );
      final restored = ERDiagram.fromJson(diag.toJson());
      expect(restored.tableCount, 1);
      expect(restored.nodes.first.tableName, 'users');
      expect(restored.createdAt, DateTime(2026, 6, 1));
    });

    test('isolatedNodes returns nodes without foreign keys', () {
      final isolated = ERNode(
        tableName: 'logs',
        primaryKeys: [],
        foreignKeys: [],
        columns: [],
        rowCount: 0,
      );
      final diag = ERDiagram(nodes: [isolated], edges: []);
      expect(diag.isolatedNodes.length, 1);
      expect(diag.connectedNodes, isEmpty);
    });

    test('relationshipCount and tableCount', () {
      final a = ERNode(
        tableName: 'a',
        primaryKeys: [],
        foreignKeys: [],
        columns: [],
        rowCount: 0,
      );
      final b = ERNode(
        tableName: 'b',
        primaryKeys: [],
        foreignKeys: [],
        columns: [],
        rowCount: 0,
      );
      final edge = EREdge(
        name: 'fk',
        fromNode: a,
        toNode: b,
        fieldMappings: [],
      );
      final diag = ERDiagram(nodes: [a, b], edges: [edge]);
      expect(diag.tableCount, 2);
      expect(diag.relationshipCount, 1);
    });

    test('copyWith updates fields', () {
      final diag = ERDiagram(
        nodes: [],
        edges: [],
        createdAt: DateTime(2026, 1, 1),
      );
      final copied = diag.copyWith(createdAt: DateTime(2026, 6, 1));
      expect(copied.createdAt, DateTime(2026, 6, 1));
    });
  });
}
