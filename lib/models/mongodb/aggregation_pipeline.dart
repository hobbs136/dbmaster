import 'package:json_annotation/json_annotation.dart';
import 'package:flutter/foundation.dart';
import 'aggregation_stage.dart';

part 'aggregation_pipeline.g.dart';

/// Represents a complete aggregation pipeline
@immutable
@JsonSerializable()
class AggregationPipeline {
  /// Target collection name
  final String collectionName;
  
  /// Ordered stages
  final List<AggregationStage> stages;
  
  /// Whether pipeline is currently executing
  final bool isRunning;
  
  /// Latest execution result (as JSON string for serialization)
  final String? result;
  
  AggregationPipeline({
    required this.collectionName,
    required this.stages,
    required this.isRunning,
    this.result,
  }) : assert(collectionName.isNotEmpty, 'Collection name must not be empty');
  
  factory AggregationPipeline.fromJson(Map<String, dynamic> json) =>
      _$AggregationPipelineFromJson(json);
  
  Map<String, dynamic> toJson() => _$AggregationPipelineToJson(this);
  
  /// Create a new pipeline for a collection
  factory AggregationPipeline.create(String collectionName) {
    return AggregationPipeline(
      collectionName: collectionName,
      stages: [],
      isRunning: false,
      result: null,
    );
  }
  
  /// Add a stage to the pipeline
  AggregationPipeline addStage(AggregationStage stage) {
    return AggregationPipeline(
      collectionName: collectionName,
      stages: [...stages, stage],
      isRunning: isRunning,
      result: result,
    );
  }
  
  /// Remove a stage by ID
  AggregationPipeline removeStage(String stageId) {
    return AggregationPipeline(
      collectionName: collectionName,
      stages: stages.where((stage) => stage.id != stageId).toList(),
      isRunning: isRunning,
      result: result,
    );
  }
  
  /// Reorder stages (move stage from fromIndex to toIndex)
  AggregationPipeline reorderStages(int fromIndex, int toIndex) {
    if (fromIndex < 0 || fromIndex >= stages.length || toIndex < 0 || toIndex >= stages.length) {
      return this; // Invalid indices, return unchanged
    }
    
    final newStages = List<AggregationStage>.from(stages);
    final stage = newStages.removeAt(fromIndex);
    newStages.insert(toIndex, stage);
    
    return AggregationPipeline(
      collectionName: collectionName,
      stages: newStages,
      isRunning: isRunning,
      result: result,
    );
  }
  
  /// Validate all stages
  bool get validateAll => stages.every((stage) => stage.isValid);
  
  /// Check if pipeline is ready to run (has stages and all are valid)
  bool get isReadyToRun => stages.isNotEmpty && validateAll && !isRunning;
  
  /// Get pipeline as list for MongoDB aggregate() call
  List<Map<String, dynamic>> get pipelineList {
    return stages.map((stage) {
      final body = stage.bodyAsMap ?? {};
      return {stage.operator: body};
    }).toList();
  }
  
  /// Create a copy with running state updated
  AggregationPipeline copyWithRunningState(bool running) {
    return AggregationPipeline(
      collectionName: collectionName,
      stages: stages,
      isRunning: running,
      result: running ? null : result, // Clear result when starting new run
    );
  }
  
  /// Create a copy with result set
  AggregationPipeline copyWithResult(String? newResult) {
    return AggregationPipeline(
      collectionName: collectionName,
      stages: stages,
      isRunning: false, // Not running after result
      result: newResult,
    );
  }
  
  /// Check if pipeline is empty (no stages)
  bool get isEmpty => stages.isEmpty;
}
