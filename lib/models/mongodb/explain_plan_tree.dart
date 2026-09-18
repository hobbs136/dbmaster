import 'package:json_annotation/json_annotation.dart';
import 'package:flutter/foundation.dart';

part 'explain_plan_tree.g.dart';

/// Represents a single node in the explain plan tree
@immutable
@JsonSerializable()
class ExplainPlanNode {
  /// Stage type (e.g., "COLLSCAN", "IXSCAN", "FETCH")
  final String stageType;
  
  /// Display label for tree node
  final String label;
  
  /// Key execution stats (docsExamined, executionTimeMillis, etc.)
  final Map<String, dynamic>? executionStats;
  
  /// Child stages (nested plans)
  final List<ExplainPlanNode> children;
  
  /// UI expansion state (not persisted, transient)
  final bool isExpanded;
  
  ExplainPlanNode({
    required this.stageType,
    required this.label,
    this.executionStats,
    required this.children,
    this.isExpanded = false,
  }) : assert(stageType.isNotEmpty, 'Stage type must not be empty'),
       assert(label.isNotEmpty, 'Label must not be empty');
  
  factory ExplainPlanNode.fromJson(Map<String, dynamic> json) =>
      _$ExplainPlanNodeFromJson(json);
  
  Map<String, dynamic> toJson() => _$ExplainPlanNodeToJson(this);
  
  /// Create ExplainPlanNode from raw explain plan output
  factory ExplainPlanNode.fromExplainOutput(Map<String, dynamic> stageData) {
    // Determine stage type
    final stageType = stageData['stage'] as String? ?? 'UNKNOWN';
    
    // Build label (stage type + additional info if available)
    final label = _buildLabel(stageType, stageData);
    
    // Extract execution stats if available
    final executionStats = stageData['executionStats'] as Map<String, dynamic>?;
    
    // Process children (inputStage or inner stages)
    final children = <ExplainPlanNode>[];
    
    // Check for inputStage (common in MongoDB explain plans)
    final inputStage = stageData['inputStage'] as Map<String, dynamic>?;
    if (inputStage != null) {
      children.add(ExplainPlanNode.fromExplainOutput(inputStage));
    }
    
    // Check for inner stages (in $lookup or similar)
    final innerStages = stageData['innerStages'] as List<dynamic>?;
    if (innerStages != null) {
      for (final stage in innerStages) {
        if (stage is Map<String, dynamic>) {
          children.add(ExplainPlanNode.fromExplainOutput(stage));
        }
      }
    }
    
    return ExplainPlanNode(
      stageType: stageType,
      label: label,
      executionStats: executionStats,
      children: children,
      isExpanded: false,
    );
  }
  
  /// Build display label for stage
  static String _buildLabel(String stageType, Map<String, dynamic> stageData) {
    // Basic label
    String label = stageType;
    
    // Add index name if IXSCAN
    if (stageType == 'IXSCAN') {
      final indexName = stageData['indexName'] as String?;
      if (indexName != null && indexName.isNotEmpty) {
        label += ': $indexName';
      }
    }
    
    // Add collection name if available
    final collection = stageData['collection'] as String?;
    if (collection != null && collection.isNotEmpty) {
      label += ' on $collection';
    }
    
    return label;
  }
  
  /// Get key execution stat if available
  dynamic getStat(String statKey) {
    return executionStats?[statKey];
  }
  
  /// Check if node has children
  bool get hasChildren => children.isNotEmpty;
  
  /// Create a copy with expanded state updated
  ExplainPlanNode copyWithExpanded(bool expanded) {
    return ExplainPlanNode(
      stageType: stageType,
      label: label,
      executionStats: executionStats,
      children: children,
      isExpanded: expanded,
    );
  }
}

/// Container for the complete explain plan tree
@immutable
@JsonSerializable()
class ExplainPlanTree {
  /// Original query string
  final String query;
  
  /// Root plan node (null if parse failed)
  final ExplainPlanNode? rootNode;
  
  /// Error message if plan parse failed
  final String? parseError;
  
  /// Total execution time
  final int? executionTimeMillis;
  
  ExplainPlanTree({
    required this.query,
    this.rootNode,
    this.parseError,
    this.executionTimeMillis,
  }) : assert(query.isNotEmpty, 'Query must not be empty'),
       assert(
         rootNode != null || parseError != null,
         'Either rootNode or parseError must be provided',
       );
  
  factory ExplainPlanTree.fromJson(Map<String, dynamic> json) =>
      _$ExplainPlanTreeFromJson(json);
  
  Map<String, dynamic> toJson() => _$ExplainPlanTreeToJson(this);
  
  /// Create ExplainPlanTree from QueryResult (from MongoDB adapter)
  factory ExplainPlanTree.fromQueryResult(String originalQuery, Map<String, dynamic> queryResult) {
    // Try to extract explain plan data from QueryResult
    // This assumes the adapter returns explain plan in a specific format
    
    try {
      // Check for error in query result
      final error = queryResult['error'] as String?;
      if (error != null && error.isNotEmpty) {
        return ExplainPlanTree(
          query: originalQuery,
          parseError: error,
        );
      }
      
      // Extract execution stats if available
      final executionStats = queryResult['executionStats'] as Map<String, dynamic>?;
      final executionTimeMillis = executionStats?['executionTimeMillis'] as int?;
      
      // Extract winning plan
      final winningPlan = queryResult['winningPlan'] as Map<String, dynamic>?;
      if (winningPlan != null) {
        final rootNode = ExplainPlanNode.fromExplainOutput(winningPlan);
        
        return ExplainPlanTree(
          query: originalQuery,
          rootNode: rootNode,
          executionTimeMillis: executionTimeMillis,
        );
      }
      
      // If we can't parse the plan structure, return error
      return ExplainPlanTree(
        query: originalQuery,
        parseError: 'Could not parse explain plan structure',
      );
    } catch (e) {
      return ExplainPlanTree(
        query: originalQuery,
        parseError: 'Failed to parse explain plan: ${e.toString()}',
      );
    }
  }
  
  /// Check if plan was parsed successfully
  bool get isParsedSuccessfully => rootNode != null && parseError == null;
  
  /// Check if parse failed
  bool get hasParseError => parseError != null && parseError!.isNotEmpty;
  
  /// Create a copy with root node expansion state updated
  ExplainPlanTree copyWithNodeExpanded(String nodePath, bool expanded) {
    if (rootNode == null) return this;
    
    // For now, simple implementation - expand root only
    // Full implementation would navigate to specific node by path
    final newRoot = rootNode!.copyWithExpanded(expanded);
    
    return ExplainPlanTree(
      query: query,
      rootNode: newRoot,
      parseError: parseError,
      executionTimeMillis: executionTimeMillis,
    );
  }
}
