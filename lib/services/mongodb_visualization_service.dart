import 'package:dbmaster/models/mongodb/inferred_schema.dart';
import 'package:dbmaster/models/mongodb/aggregation_stage.dart';
import 'package:dbmaster/models/mongodb/aggregation_pipeline.dart';
import 'package:dbmaster/models/mongodb/explain_plan_tree.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/services/adapters/mongodb_adapter.dart';
import 'package:dbmaster/utils/app_logger.dart';

/// Service for MongoDB visualization features
/// Handles data preparation for Schema, Pipeline, and Explain Plan views
class MongoVisualizationService {
  final AppProvider _appProvider;

  const MongoVisualizationService(this._appProvider);

  /// Load schema for a collection
  Future<InferredDocumentSchema> loadSchema(String collectionName) async {
    try {
      AppLogger.d('MongoVisualizationService', 'Loading schema for collection: $collectionName');
      
      final adapter = _appProvider.dbService.currentAdapter;
      if (adapter is! MongoDBAdapter) {
        throw Exception('MongoDB adapter not available');
      }

      final schemaData = await adapter.inferDocumentSchema(collectionName);
      final schema = InferredDocumentSchema.fromAdapterOutput(schemaData);
      
      AppLogger.d('MongoVisualizationService', 'Schema loaded: ${schema.fields.length} fields');
      return schema;
    } catch (e, stackTrace) {
      AppLogger.e('MongoVisualizationService', 'Failed to load schema', e, stackTrace);
      rethrow;
    }
  }

  /// Create a new aggregation pipeline
  AggregationPipeline createPipeline(String collectionName) {
    AppLogger.d('MongoVisualizationService', 'Creating pipeline for collection: $collectionName');
    return AggregationPipeline.create(collectionName);
  }

  /// Add a stage to pipeline
  AggregationPipeline addStage(AggregationPipeline pipeline, String operator, String jsonBody) {
    final stage = AggregationStage.create(operator: operator, jsonBody: jsonBody);
    AppLogger.d('MongoVisualizationService', 'Adding stage: ${stage.operator}');
    return pipeline.addStage(stage);
  }

  /// Remove a stage from pipeline
  AggregationPipeline removeStage(AggregationPipeline pipeline, String stageId) {
    AppLogger.d('MongoVisualizationService', 'Removing stage: $stageId');
    return pipeline.removeStage(stageId);
  }

  /// Reorder stages in pipeline
  AggregationPipeline reorderStages(AggregationPipeline pipeline, int fromIndex, int toIndex) {
    AppLogger.d('MongoVisualizationService', 'Reordering stages: $fromIndex -> $toIndex');
    return pipeline.reorderStages(fromIndex, toIndex);
  }

  /// Run aggregation pipeline
  Future<Map<String, dynamic>> runPipeline(AggregationPipeline pipeline) async {
    try {
      AppLogger.d('MongoVisualizationService', 'Running pipeline with ${pipeline.stages.length} stages');
      
      final adapter = _appProvider.dbService.currentAdapter;
      if (adapter is! MongoDBAdapter) {
        throw Exception('MongoDB adapter not available');
      }

      if (!pipeline.isReadyToRun) {
        throw Exception('Pipeline is not ready to run');
      }

      final pipelineList = pipeline.pipelineList;
      final result = await adapter.aggregate(pipeline.collectionName, pipelineList);
      
      AppLogger.d('MongoVisualizationService', 'Pipeline completed successfully');
      return {
        'success': true,
        'result': result,
        'stageCount': pipeline.stages.length,
      };
    } catch (e, stackTrace) {
      AppLogger.e('MongoVisualizationService', 'Pipeline execution failed', e, stackTrace);
      return {
        'success': false,
        'error': e.toString(),
      };
    }
  }

  /// Load explain plan for a query
  Future<ExplainPlanTree> loadExplainPlan(String query) async {
    try {
      AppLogger.d('MongoVisualizationService', 'Loading explain plan for query');
      
      final adapter = _appProvider.dbService.currentAdapter;
      if (adapter is! MongoDBAdapter) {
        throw Exception('MongoDB adapter not available');
      }

      final queryResult = await adapter.getExplainPlan(query);
      
      // Convert QueryResult to Map for parsing
      final resultMap = {
        'query': query,
        'rows': queryResult.rows,
        'columnNames': queryResult.columns,
        'error': queryResult.message,
      };
      
      final explainPlan = ExplainPlanTree.fromQueryResult(query, resultMap);
      
      AppLogger.d('MongoVisualizationService', 'Explain plan loaded: ${explainPlan.isParsedSuccessfully}');
      return explainPlan;
    } catch (e, stackTrace) {
      AppLogger.e('MongoVisualizationService', 'Failed to load explain plan', e, stackTrace);
      rethrow;
    }
  }
}
