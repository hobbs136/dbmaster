import 'package:json_annotation/json_annotation.dart';
import 'package:flutter/foundation.dart';
import 'dart:convert';

part 'aggregation_stage.g.dart';

/// Represents a single stage in an aggregation pipeline
@immutable
@JsonSerializable()
class AggregationStage {
  /// Unique stage ID (UUID)
  final String id;
  
  /// Stage operator (e.g., "$match", "$group")
  final String operator;
  
  /// Stage body as JSON string
  final String jsonBody;
  
  /// Whether JSON is syntactically valid
  final bool isValid;
  
  /// Error message if !isValid
  final String? errorMessage;
  
  AggregationStage({
    required this.id,
    required this.operator,
    required this.jsonBody,
    required this.isValid,
    this.errorMessage,
  }) : assert(operator.startsWith('\$'), 'Operator must start with \$'),
       assert(
         isValid || (errorMessage != null && errorMessage!.isNotEmpty),
         'Error message required when stage is invalid',
       );
  
  factory AggregationStage.fromJson(Map<String, dynamic> json) =>
      _$AggregationStageFromJson(json);
  
  Map<String, dynamic> toJson() => _$AggregationStageToJson(this);
  
  /// Create a new aggregation stage
  factory AggregationStage.create({required String operator, required String jsonBody}) {
    // Validate operator starts with $
    final op = operator.startsWith('\$') ? operator : '\$$operator';
    
    // Validate JSON syntax
    String? errorMessage;
    bool isValid = true;
    
    try {
      // Try to parse the JSON
      final parsed = jsonDecode(jsonBody);
      // Ensure it's a Map (stage body)
      if (parsed is! Map<String, dynamic>) {
        isValid = false;
        errorMessage = 'Stage body must be a JSON object';
      }
    } catch (e) {
      isValid = false;
      errorMessage = 'Invalid JSON: ${e.toString()}';
    }
    
    return AggregationStage(
      id: _generateUUID(),
      operator: op,
      jsonBody: jsonBody,
      isValid: isValid,
      errorMessage: errorMessage,
    );
  }
  
  /// Generate a simple UUID (for stage identification)
  static String _generateUUID() {
    return 'stage_${DateTime.now().millisecondsSinceEpoch}_${Object().hashCode}';
  }
  
  /// Get the stage body as a Map (only if valid)
  Map<String, dynamic>? get bodyAsMap {
    if (!isValid) return null;
    
    try {
      final parsed = jsonDecode(jsonBody);
      return parsed as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }
  
  /// Create a copy with updated values
  AggregationStage copyWith({
    String? operator,
    String? jsonBody,
    bool? isValid,
    String? errorMessage,
  }) {
    // Re-validate if jsonBody or operator changes
    String newJsonBody = jsonBody ?? this.jsonBody;
    String newOperator = operator ?? this.operator;
    bool newIsValid = isValid ?? this.isValid;
    String? newErrorMessage = errorMessage ?? this.errorMessage;
    
    if (jsonBody != null && jsonBody != this.jsonBody) {
      // JSON changed, re-validate
      final newStage = AggregationStage.create(
        operator: newOperator,
        jsonBody: newJsonBody,
      );
      return AggregationStage(
        id: id,
        operator: newStage.operator,
        jsonBody: newStage.jsonBody,
        isValid: newStage.isValid,
        errorMessage: newStage.errorMessage,
      );
    }
    
    return AggregationStage(
      id: id,
      operator: newOperator,
      jsonBody: newJsonBody,
      isValid: newIsValid,
      errorMessage: newErrorMessage,
    );
  }
}
