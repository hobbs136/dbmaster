import 'dart:math';
import 'package:flutter/material.dart';
import '../models/er_diagram.dart';

class ERLayoutService {
  static const double _nodeSpacing = 250.0;
  static const double _levelSpacing = 300.0;
  static const double _circleRadius = 400.0;

  /// Apply force-directed layout to the diagram
  /// Uses a physics simulation to position nodes
  void applyForceDirectedLayout({
    required List<ERNode> nodes,
    required List<EREdge> edges,
    Size canvasSize = const Size(2000, 1500),
    int iterations = 100,
  }) {
    if (nodes.isEmpty) return;

    // Initialize positions if not set
    _initializePositions(nodes, canvasSize);

    // Build adjacency list
    final adjacency = _buildAdjacencyList(nodes, edges);

    // Apply forces
    for (int i = 0; i < iterations; i++) {
      _applyForces(nodes, adjacency, canvasSize);
    }

    // Center the diagram
    _centerDiagram(nodes, canvasSize);
  }

  /// Apply hierarchical layout to the diagram
  /// Arranges nodes in levels based on relationships
  void applyHierarchicalLayout({
    required List<ERNode> nodes,
    required List<EREdge> edges,
    Size canvasSize = const Size(2000, 1500),
  }) {
    if (nodes.isEmpty) return;

    // Build a graph representation
    final graph = _buildGraph(nodes, edges);

    // Find root nodes (nodes with no incoming edges from isolated groups)
    final roots = _findRootNodes(nodes, edges);

    // If no roots found, pick arbitrary nodes as roots
    final startNodes = roots.isEmpty ? [nodes.first] : roots;

    // Assign levels using BFS
    final levels = <int, List<ERNode>>{};
    final visited = <ERNode>{};
    final queue = <ERNode>[];

    // Initialize queue with root nodes at level 0
    for (final root in startNodes) {
      queue.add(root);
      levels[0] = (levels[0] ?? []) + [root];
      visited.add(root);
    }

    // BFS to assign levels
    int maxLevel = 0;
    while (queue.isNotEmpty) {
      final current = queue.removeAt(0);
      final currentLevel = levels.entries
          .firstWhere((entry) => entry.value.contains(current))
          .key;

      // Get neighbors (both incoming and outgoing)
      final neighbors = graph[current] ?? [];

      for (final neighbor in neighbors) {
        if (!visited.contains(neighbor)) {
          visited.add(neighbor);
          final nextLevel = currentLevel + 1;
          levels[nextLevel] = (levels[nextLevel] ?? []) + [neighbor];
          queue.add(neighbor);
          maxLevel = max(maxLevel, nextLevel);
        }
      }
    }

    // Add any unvisited nodes as isolated at the end
    for (final node in nodes) {
      if (!visited.contains(node)) {
        maxLevel = max(maxLevel, 1);
        levels[maxLevel] = (levels[maxLevel] ?? []) + [node];
      }
    }

    // Position nodes by level
    final levelWidths = <int, double>{};
    for (final entry in levels.entries) {
      final level = entry.key;
      final nodesInLevel = entry.value;
      levelWidths[level] = (nodesInLevel.length * _nodeSpacing) / 2;
    }

    final startY = 100.0;

    for (final entry in levels.entries) {
      final level = entry.key;
      final nodesInLevel = entry.value;
      final levelY = startY + (level * _levelSpacing);

      // Calculate start X for this level to center it
      final levelWidth = (nodesInLevel.length * _nodeSpacing);
      final levelStartX = (canvasSize.width - levelWidth) / 2;

      for (int i = 0; i < nodesInLevel.length; i++) {
        nodesInLevel[i].position = Offset(
          levelStartX + (i * _nodeSpacing),
          levelY,
        );
      }
    }
  }

  /// Apply circle layout to the diagram
  /// Arranges nodes in a circle around center
  void applyCircleLayout({
    required List<ERNode> nodes,
    Size canvasSize = const Size(2000, 1500),
  }) {
    if (nodes.isEmpty) return;

    final center = Offset(canvasSize.width / 2, canvasSize.height / 2);
    final count = nodes.length;
    final angleStep = (2 * pi) / count;

    for (int i = 0; i < count; i++) {
      final angle = i * angleStep;
      nodes[i].position = Offset(
        center.dx + _circleRadius * cos(angle),
        center.dy + _circleRadius * sin(angle),
      );
    }
  }

  /// Reset all nodes to center of canvas
  void resetLayout({
    required List<ERNode> nodes,
    Size canvasSize = const Size(2000, 1500),
  }) {
    if (nodes.isEmpty) return;

    final center = Offset(canvasSize.width / 2, canvasSize.height / 2);
    final count = nodes.length;
    final cols = sqrt(count).ceil();
    final rows = (count / cols).ceil();

    final startX = center.dx - (cols * _nodeSpacing) / 2;
    final startY = center.dy - (rows * _levelSpacing) / 2;

    for (int i = 0; i < count; i++) {
      final col = i % cols;
      final row = i ~/ cols;
      nodes[i].position = Offset(
        startX + (col * _nodeSpacing),
        startY + (row * _levelSpacing),
      );
    }
  }

  /// Initialize node positions if not set
  void _initializePositions(List<ERNode> nodes, Size canvasSize) {
    final hasUninitializedPositions = nodes.any(
      (node) => node.position == Offset.zero,
    );

    if (hasUninitializedPositions) {
      resetLayout(nodes: nodes, canvasSize: canvasSize);
    }
  }

  /// Build adjacency list for force simulation
  Map<ERNode, List<ERNode>> _buildAdjacencyList(
    List<ERNode> nodes,
    List<EREdge> edges,
  ) {
    final adjacency = <ERNode, List<ERNode>>{};

    // Initialize empty lists
    for (final node in nodes) {
      adjacency[node] = [];
    }

    // Add edges
    for (final edge in edges) {
      adjacency[edge.fromNode]!.add(edge.toNode);
      adjacency[edge.toNode]!.add(edge.fromNode); // Undirected for layout
    }

    return adjacency;
  }

  /// Build directed graph for hierarchical layout
  Map<ERNode, List<ERNode>> _buildGraph(
    List<ERNode> nodes,
    List<EREdge> edges,
  ) {
    final graph = <ERNode, List<ERNode>>{};

    // Initialize empty lists
    for (final node in nodes) {
      graph[node] = [];
    }

    // Add directed edges (from foreign key to referenced table)
    for (final edge in edges) {
      graph[edge.fromNode]!.add(edge.toNode);
    }

    return graph;
  }

  /// Find root nodes (nodes with no incoming edges)
  List<ERNode> _findRootNodes(List<ERNode> nodes, List<EREdge> edges) {
    final hasIncoming = <ERNode, bool>{};

    // Initialize
    for (final node in nodes) {
      hasIncoming[node] = false;
    }

    // Mark nodes with incoming edges
    for (final edge in edges) {
      hasIncoming[edge.toNode] = true;
    }

    // Return nodes with no incoming edges
    return nodes.where((node) => !hasIncoming[node]!).toList();
  }

  /// Apply repulsion and attraction forces
  void _applyForces(
    List<ERNode> nodes,
    Map<ERNode, List<ERNode>> adjacency,
    Size canvasSize,
  ) {
    const repulsionStrength = 10000.0;
    const attractionStrength = 0.01;
    const damping = 0.9;
    const temperature = 0.1;

    // Calculate forces
    final forces = <ERNode, Offset>{};

    for (final node in nodes) {
      forces[node] = Offset.zero;
    }

    // Repulsion between all nodes
    for (int i = 0; i < nodes.length; i++) {
      for (int j = i + 1; j < nodes.length; j++) {
        final nodeA = nodes[i];
        final nodeB = nodes[j];

        final dx = nodeB.position.dx - nodeA.position.dx;
        final dy = nodeB.position.dy - nodeA.position.dy;
        final distance = sqrt(dx * dx + dy * dy);

        if (distance < 0.1) continue; // Avoid division by zero

        final force = repulsionStrength / (distance * distance);
        final fx = (dx / distance) * force;
        final fy = (dy / distance) * force;

        forces[nodeA] = forces[nodeA]! - Offset(fx, fy);
        forces[nodeB] = forces[nodeB]! + Offset(fx, fy);
      }
    }

    // Attraction along edges
    for (final edge in adjacency.entries) {
      final node = edge.key;
      final neighbors = edge.value;

      for (final neighbor in neighbors) {
        final dx = neighbor.position.dx - node.position.dx;
        final dy = neighbor.position.dy - node.position.dy;
        final distance = sqrt(dx * dx + dy * dy);

        if (distance < 0.1) continue;

        final force = attractionStrength * distance;
        final fx = (dx / distance) * force;
        final fy = (dy / distance) * force;

        forces[node] = forces[node]! + Offset(fx, fy);
      }
    }

    // Apply forces with new positions
    for (final node in nodes) {
      final force = forces[node]!;
      node.position = Offset(
        node.position.dx + force.dx * temperature * damping,
        node.position.dy + force.dy * temperature * damping,
      );
    }
  }

  /// Center the diagram in the canvas
  void _centerDiagram(List<ERNode> nodes, Size canvasSize) {
    if (nodes.isEmpty) return;

    // Calculate bounding box
    double minX = double.infinity;
    double minY = double.infinity;
    double maxX = double.negativeInfinity;
    double maxY = double.negativeInfinity;

    for (final node in nodes) {
      minX = min(minX, node.position.dx);
      minY = min(minY, node.position.dy);
      maxX = max(maxX, node.position.dx + node.size.width);
      maxY = max(maxY, node.position.dy + node.size.height);
    }

    final diagramWidth = maxX - minX;
    final diagramHeight = maxY - minY;

    // Calculate offset to center
    final offsetX = (canvasSize.width - diagramWidth) / 2 - minX;
    final offsetY = (canvasSize.height - diagramHeight) / 2 - minY;

    // Apply offset
    for (final node in nodes) {
      node.position = Offset(
        node.position.dx + offsetX,
        node.position.dy + offsetY,
      );
    }
  }
}
