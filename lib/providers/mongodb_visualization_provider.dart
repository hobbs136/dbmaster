import 'package:flutter/foundation.dart';
import 'package:dbmaster/models/mongodb/inferred_schema.dart';
import 'package:dbmaster/models/mongodb/aggregation_pipeline.dart';
import 'package:dbmaster/models/mongodb/explain_plan_tree.dart';
import 'package:dbmaster/providers/app_provider.dart';
import 'package:dbmaster/services/mongodb_visualization_service.dart';
import 'package:dbmaster/utils/app_logger.dart';

/// Provider for MongoDB visualization features
/// Manages state for Schema, Pipeline, and Explain Plan views
class MongoVisualizationProvider extends ChangeNotifier {
  final AppProvider _appProvider;
  late MongoVisualizationService _service;

  // Schema state
  InferredDocumentSchema? _currentSchema;
  bool _loadingSchema = false;
  String? _schemaError;

  // Pipeline state
  AggregationPipeline? _currentPipeline;
  bool _pipelineRunning = false;
  String? _pipelineResult;
  String? _pipelineError;

  // Explain plan state
  ExplainPlanTree? _currentExplainPlan;
  bool _explainLoading = false;
  String? _explainError;

  MongoVisualizationProvider(this._appProvider) {
    _service = MongoVisualizationService(_appProvider);
  }

  // ========== Schema View ==========

  InferredDocumentSchema? get currentSchema => _currentSchema;
  bool get loadingSchema => _loadingSchema;
  String? get schemaError => _schemaError;

  Future<void> loadSchema(String collectionName) async {
    _loadingSchema = true;
    _schemaError = null;
    notifyListeners();

    try {
      final schema = await _service.loadSchema(collectionName);
      _currentSchema = schema;
      AppLogger.d('MongoVisualizationProvider', 'Schema loaded: ${schema.fields.length} fields');
    } catch (e, stackTrace) {
      _schemaError = 'Failed to load schema: ${e.toString()}';
      AppLogger.e('MongoVisualizationProvider', 'Schema load failed', e, stackTrace);
    } finally {
      _loadingSchema = false;
      notifyListeners();
    }
  }

  void clearSchema() {
    _currentSchema = null;
    _schemaError = null;
    notifyListeners();
  }

  @visibleForTesting
  void setSchemaForTest(InferredDocumentSchema? schema) {
    _currentSchema = schema;
    notifyListeners();
  }

  @visibleForTesting
  void setLoadingSchemaForTest(bool loading) {
    _loadingSchema = loading;
    notifyListeners();
  }

  @visibleForTesting
  void setSchemaErrorForTest(String? error) {
    _schemaError = error;
    notifyListeners();
  }

  // ========== Pipeline Builder ==========

  AggregationPipeline? get currentPipeline => _currentPipeline;
  bool get pipelineRunning => _pipelineRunning;
  String? get pipelineResult => _pipelineResult;
  String? get pipelineError => _pipelineError;

  void createPipeline(String collectionName) {
    _currentPipeline = _service.createPipeline(collectionName);
    _pipelineError = null;
    notifyListeners();
  }

  void updatePipeline(AggregationPipeline pipeline) {
    _currentPipeline = pipeline;
    notifyListeners();
  }

  Future<void> runPipeline() async {
    if (_currentPipeline == null || _pipelineRunning) {
      return;
    }

    _pipelineRunning = true;
    _pipelineError = null;
    _pipelineResult = null;
    notifyListeners();

    try {
      final result = await _service.runPipeline(_currentPipeline!);
      
      if (result['success'] == true) {
        _pipelineResult = 'Pipeline executed successfully';
        AppLogger.d('MongoVisualizationProvider', 'Pipeline completed');
      } else {
        _pipelineError = result['error']?.toString() ?? 'Pipeline execution failed';
        AppLogger.e('MongoVisualizationProvider', 'Pipeline failed: $_pipelineError');
      }

      // Update pipeline state
      _currentPipeline = _currentPipeline!.copyWithRunningState(false);
    } catch (e, stackTrace) {
      _pipelineError = 'Pipeline execution error: ${e.toString()}';
      AppLogger.e('MongoVisualizationProvider', 'Pipeline error', e, stackTrace);
      _currentPipeline = _currentPipeline!.copyWithRunningState(false);
    } finally {
      _pipelineRunning = false;
      notifyListeners();
    }
  }

  void cancelPipeline() {
    if (_currentPipeline != null && _pipelineRunning) {
      _currentPipeline = _currentPipeline!.copyWithRunningState(false);
      _pipelineRunning = false;
      _pipelineResult = 'Pipeline cancelled';
      notifyListeners();
      AppLogger.d('MongoVisualizationProvider', 'Pipeline cancelled');
    }
  }

  void clearPipeline() {
    _currentPipeline = null;
    _pipelineRunning = false;
    _pipelineResult = null;
    _pipelineError = null;
    notifyListeners();
  }

  // ========== Explain Plan ==========

  ExplainPlanTree? get currentExplainPlan => _currentExplainPlan;
  bool get explainLoading => _explainLoading;
  String? get explainError => _explainError;

  Future<void> loadExplainPlan(String query) async {
    _explainLoading = true;
    _explainError = null;
    notifyListeners();

    try {
      final explainPlan = await _service.loadExplainPlan(query);
      _currentExplainPlan = explainPlan;
      AppLogger.d('MongoVisualizationProvider', 'Explain plan loaded: ${explainPlan.isParsedSuccessfully}');
    } catch (e, stackTrace) {
      _explainError = 'Failed to load explain plan: ${e.toString()}';
      AppLogger.e('MongoVisualizationProvider', 'Explain plan load failed', e, stackTrace);
    } finally {
      _explainLoading = false;
      notifyListeners();
    }
  }

  void clearExplainPlan() {
    _currentExplainPlan = null;
    _explainError = null;
    notifyListeners();
  }

  // ========== Cleanup ==========

  @override
  void dispose() {
    _currentSchema = null;
    _currentPipeline = null;
    _currentExplainPlan = null;
    super.dispose();
  }
}
