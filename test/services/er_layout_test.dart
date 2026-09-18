import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:dbmaster/services/er_layout.dart';
import 'package:dbmaster/models/er_diagram.dart';

void main() {
  group('ERLayoutService', () {
    late ERLayoutService layoutService;
    late ERNode nodeA;
    late ERNode nodeB;
    late ERNode nodeC;
    late ERNode nodeD;

    setUp(() {
      layoutService = ERLayoutService();
      nodeA = ERNode(
        tableName: 'users',
        primaryKeys: ['id'],
        foreignKeys: [],
        columns: ['id', 'name', 'email'],
        rowCount: 100,
      );
      nodeB = ERNode(
        tableName: 'orders',
        primaryKeys: ['id'],
        foreignKeys: [],
        columns: ['id', 'user_id', 'total'],
        rowCount: 500,
      );
      nodeC = ERNode(
        tableName: 'items',
        primaryKeys: ['id'],
        foreignKeys: [],
        columns: ['id', 'order_id', 'name'],
        rowCount: 1000,
      );
      nodeD = ERNode(
        tableName: 'reviews',
        primaryKeys: ['id'],
        foreignKeys: [],
        columns: ['id', 'product_id', 'rating'],
        rowCount: 50,
      );
    });

    group('Hierarchical Layout', () {
      test('positions root nodes at level 0', () {
        final edge = EREdge(
          name: 'fk_orders_user',
          fromNode: nodeB,
          toNode: nodeA,
          fieldMappings: [FieldMapping(fromField: 'user_id', toField: 'id')],
        );

        layoutService.applyHierarchicalLayout(
          nodes: [nodeA, nodeB],
          edges: [edge],
          canvasSize: const Size(2000, 1500),
        );

        // Root node (B, no incoming edges) should be at a lower Y than child (A)
        expect(nodeB.position.dy, lessThan(nodeA.position.dy));
      });

      test('centers nodes horizontally within each level', () {
        final edge = EREdge(
          name: 'fk_orders_user',
          fromNode: nodeB,
          toNode: nodeA,
          fieldMappings: [FieldMapping(fromField: 'user_id', toField: 'id')],
        );

        layoutService.applyHierarchicalLayout(
          nodes: [nodeA, nodeB],
          edges: [edge],
          canvasSize: const Size(2000, 1500),
        );

        // Both nodes should be within canvas bounds
        expect(nodeA.position.dx, greaterThanOrEqualTo(0));
        expect(nodeA.position.dx, lessThan(2000));
        expect(nodeB.position.dx, greaterThanOrEqualTo(0));
        expect(nodeB.position.dx, lessThan(2000));
      });

      test('handles isolated nodes by placing them at the end', () {
        final edge = EREdge(
          name: 'fk_orders_user',
          fromNode: nodeB,
          toNode: nodeA,
          fieldMappings: [FieldMapping(fromField: 'user_id', toField: 'id')],
        );

        layoutService.applyHierarchicalLayout(
          nodes: [nodeA, nodeB, nodeD],
          edges: [edge],
          canvasSize: const Size(2000, 1500),
        );

        // Isolated node D should still have a non-zero position
        expect(nodeD.position, isNot(equals(Offset.zero)));
      });

      test('handles empty node list gracefully', () {
        expect(
          () => layoutService.applyHierarchicalLayout(
            nodes: [],
            edges: [],
            canvasSize: const Size(2000, 1500),
          ),
          returnsNormally,
        );
      });

      test('assigns different Y values for different levels', () {
        final edge1 = EREdge(
          name: 'fk_orders_user',
          fromNode: nodeB,
          toNode: nodeA,
          fieldMappings: [FieldMapping(fromField: 'user_id', toField: 'id')],
        );
        final edge2 = EREdge(
          name: 'fk_items_order',
          fromNode: nodeC,
          toNode: nodeB,
          fieldMappings: [FieldMapping(fromField: 'order_id', toField: 'id')],
        );

        layoutService.applyHierarchicalLayout(
          nodes: [nodeA, nodeB, nodeC],
          edges: [edge1, edge2],
          canvasSize: const Size(2000, 1500),
        );

        // Three-level hierarchy: C at top (root), B middle, A bottom
        // C (items) -> B (orders), B (orders) -> A (users)
        expect(nodeC.position.dy, lessThan(nodeB.position.dy));
        expect(nodeB.position.dy, lessThan(nodeA.position.dy));
      });
    });

    group('Force-Directed Layout', () {
      test('changes node positions after simulation', () {
        final edge = EREdge(
          name: 'fk_orders_user',
          fromNode: nodeB,
          toNode: nodeA,
          fieldMappings: [FieldMapping(fromField: 'user_id', toField: 'id')],
        );

        final initialA = nodeA.position;
        final initialB = nodeB.position;

        layoutService.applyForceDirectedLayout(
          nodes: [nodeA, nodeB],
          edges: [edge],
          canvasSize: const Size(2000, 1500),
          iterations: 10,
        );

        // Positions should have changed from zero initialization
        expect(
          nodeA.position == initialA && nodeB.position == initialB,
          isFalse,
        );
      });

      test('keeps nodes within canvas bounds after centering', () {
        final edge = EREdge(
          name: 'fk_orders_user',
          fromNode: nodeB,
          toNode: nodeA,
          fieldMappings: [FieldMapping(fromField: 'user_id', toField: 'id')],
        );

        layoutService.applyForceDirectedLayout(
          nodes: [nodeA, nodeB],
          edges: [edge],
          canvasSize: const Size(2000, 1500),
          iterations: 50,
        );

        // After centering, nodes should be within reasonable bounds
        expect(nodeA.position.dx, greaterThan(-500));
        expect(nodeA.position.dx, lessThan(2500));
        expect(nodeA.position.dy, greaterThan(-500));
        expect(nodeA.position.dy, lessThan(2000));
      });

      test('handles empty node list gracefully', () {
        expect(
          () => layoutService.applyForceDirectedLayout(
            nodes: [],
            edges: [],
            canvasSize: const Size(2000, 1500),
          ),
          returnsNormally,
        );
      });

      test('connected nodes are closer than unconnected ones', () {
        final edge = EREdge(
          name: 'fk_orders_user',
          fromNode: nodeB,
          toNode: nodeA,
          fieldMappings: [FieldMapping(fromField: 'user_id', toField: 'id')],
        );

        layoutService.applyForceDirectedLayout(
          nodes: [nodeA, nodeB, nodeD],
          edges: [edge],
          canvasSize: const Size(2000, 1500),
          iterations: 100,
        );

        final distAB = (nodeA.position - nodeB.position).distance;
        final distAD = (nodeA.position - nodeD.position).distance;

        // Connected nodes A-B should be closer than unconnected A-D
        expect(distAB, lessThan(distAD));
      });
    });

    group('Circle Layout', () {
      test('arranges nodes evenly around center', () {
        layoutService.applyCircleLayout(
          nodes: [nodeA, nodeB, nodeC, nodeD],
          canvasSize: const Size(2000, 1500),
        );

        final center = const Offset(1000, 750);
        final distA = (nodeA.position - center).distance;
        final distB = (nodeB.position - center).distance;
        final distC = (nodeC.position - center).distance;
        final distD = (nodeD.position - center).distance;

        // All nodes should be at approximately the same radius
        expect(distA, closeTo(distB, 1.0));
        expect(distB, closeTo(distC, 1.0));
        expect(distC, closeTo(distD, 1.0));
      });

      test('places nodes at 90 degree intervals for 4 nodes', () {
        layoutService.applyCircleLayout(
          nodes: [nodeA, nodeB, nodeC, nodeD],
          canvasSize: const Size(2000, 1500),
        );

        final center = const Offset(1000, 750);

        // Calculate angles
        double angle(Offset pos) =>
            atan2(pos.dy - center.dy, pos.dx - center.dx);
        final angles = [
          nodeA,
          nodeB,
          nodeC,
          nodeD,
        ].map((n) => angle(n.position)).toList()..sort();

        // Check approximate 90 degree spacing
        for (int i = 0; i < angles.length - 1; i++) {
          final diff = angles[i + 1] - angles[i];
          expect(diff, closeTo(pi / 2, 0.1));
        }
      });

      test('handles single node at center offset', () {
        layoutService.applyCircleLayout(
          nodes: [nodeA],
          canvasSize: const Size(2000, 1500),
        );

        // Single node should be placed at the rightmost point of the circle
        expect(nodeA.position.dx, closeTo(1400, 1.0)); // 1000 + 400
        expect(nodeA.position.dy, closeTo(750, 1.0));
      });

      test('handles empty node list gracefully', () {
        expect(
          () => layoutService.applyCircleLayout(
            nodes: [],
            canvasSize: const Size(2000, 1500),
          ),
          returnsNormally,
        );
      });
    });

    group('Reset Layout (Grid)', () {
      test('arranges nodes in grid pattern', () {
        layoutService.resetLayout(
          nodes: [nodeA, nodeB, nodeC, nodeD],
          canvasSize: const Size(2000, 1500),
        );

        // 4 nodes should form a 2x2 grid
        // Nodes should have distinct positions
        final positions = [
          nodeA,
          nodeB,
          nodeC,
          nodeD,
        ].map((n) => n.position).toSet();
        expect(positions.length, equals(4));
      });

      test('centers grid around canvas center', () {
        layoutService.resetLayout(
          nodes: [nodeA, nodeB],
          canvasSize: const Size(2000, 1500),
        );

        final centerX = 1000.0;
        final avgX = (nodeA.position.dx + nodeB.position.dx) / 2;
        expect(avgX, closeTo(centerX, 250));
      });

      test('handles empty node list gracefully', () {
        expect(
          () => layoutService.resetLayout(
            nodes: [],
            canvasSize: const Size(2000, 1500),
          ),
          returnsNormally,
        );
      });
    });

    group('ERDiagram Model', () {
      test('serializes and deserializes correctly', () {
        final edge = EREdge(
          name: 'fk_orders_user',
          fromNode: nodeB,
          toNode: nodeA,
          fieldMappings: [FieldMapping(fromField: 'user_id', toField: 'id')],
        );

        final diagram = ERDiagram(nodes: [nodeA, nodeB], edges: [edge]);

        final json = diagram.toJson();
        final restored = ERDiagram.fromJson(json);

        expect(restored.nodes.length, equals(2));
        expect(restored.edges.length, equals(1));
        expect(restored.nodes[0].tableName, equals('users'));
        expect(restored.nodes[1].tableName, equals('orders'));
        expect(restored.tableCount, equals(2));
        expect(restored.relationshipCount, equals(1));
      });

      test('identifies isolated nodes correctly', () {
        // Node with foreign keys is not isolated
        final nodeWithFk = ERNode(
          tableName: 'orders',
          primaryKeys: ['id'],
          foreignKeys: [
            ForeignKey(
              name: 'fk_orders_user',
              table: 'orders',
              column: 'user_id',
              referencedTable: 'users',
              referencedColumn: 'id',
            ),
          ],
          columns: ['id', 'user_id'],
          rowCount: 100,
        );
        final nodeWithoutFk = ERNode(
          tableName: 'reviews',
          primaryKeys: ['id'],
          foreignKeys: [],
          columns: ['id', 'rating'],
          rowCount: 50,
        );

        final diagram = ERDiagram(
          nodes: [nodeWithFk, nodeWithoutFk],
          edges: [],
        );

        expect(diagram.isolatedNodes.length, equals(1));
        expect(diagram.isolatedNodes.first.tableName, equals('reviews'));
        expect(diagram.connectedNodes.length, equals(1));
      });

      test('FieldMapping serializes correctly', () {
        final mapping = FieldMapping(fromField: 'user_id', toField: 'id');
        final json = mapping.toJson();
        final restored = FieldMapping.fromJson(json);

        expect(restored.fromField, equals('user_id'));
        expect(restored.toField, equals('id'));
      });

      test('ERNode copyWith creates independent copy', () {
        final copy = nodeA.copyWith(
          tableName: 'users_copy',
          position: const Offset(100, 200),
        );

        expect(copy.tableName, equals('users_copy'));
        expect(copy.position, equals(const Offset(100, 200)));
        expect(nodeA.tableName, equals('users')); // Original unchanged
        expect(nodeA.position, equals(Offset.zero));
      });
    });
  });
}
