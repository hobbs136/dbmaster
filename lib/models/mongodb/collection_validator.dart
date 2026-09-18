import 'package:json_annotation/json_annotation.dart';
import 'package:flutter/foundation.dart';

part 'collection_validator.g.dart';

/// Validator type for MongoDB collections
enum ValidatorType {
  @JsonValue('jsonSchema')
  jsonSchema,
  @JsonValue('none')
  none,
}

/// Validation strictness level
enum ValidationLevel {
  @JsonValue('strict')
  strict,
  @JsonValue('moderate')
  moderate,
  @JsonValue('off')
  off,
}

/// Action on validation failure
enum ValidationAction {
  @JsonValue('error')
  error,
  @JsonValue('warn')
  warn,
}

/// Represents validation rules for a MongoDB collection
@immutable
@JsonSerializable()
class CollectionValidator {
  /// Collection name (for context)
  final String collectionName;

  /// Type of validator
  final ValidatorType validatorType;

  /// The $jsonSchema object (null if no validator)
  final Map<String, Object?>? jsonSchema;

  /// Validation strictness
  final ValidationLevel validationLevel;

  /// Action on validation failure
  final ValidationAction validationAction;

  CollectionValidator({
    required this.collectionName,
    required this.validatorType,
    this.jsonSchema,
    this.validationLevel = ValidationLevel.off,
    this.validationAction = ValidationAction.warn,
  })  : assert(
          validatorType == ValidatorType.none ? jsonSchema == null : jsonSchema != null,
          'jsonSchema must be null for NONE validator type, non-null for JSON_SCHEMA',
        );

  factory CollectionValidator.fromJson(Map<String, dynamic> json) =>
      _$CollectionValidatorFromJson(json);

  Map<String, dynamic> toJson() => _$CollectionValidatorToJson(this);

  /// Create a validator with no validation rules
  factory CollectionValidator.none(String collectionName) {
    return CollectionValidator(
      collectionName: collectionName,
      validatorType: ValidatorType.none,
      jsonSchema: null,
      validationLevel: ValidationLevel.off,
      validationAction: ValidationAction.warn,
    );
  }

  /// Create a validator with JSON schema
  factory CollectionValidator.withSchema({
    required String collectionName,
    required Map<String, Object?> schema,
    ValidationLevel level = ValidationLevel.strict,
    ValidationAction action = ValidationAction.error,
  }) {
    return CollectionValidator(
      collectionName: collectionName,
      validatorType: ValidatorType.jsonSchema,
      jsonSchema: {'\$jsonSchema': schema},
      validationLevel: level,
      validationAction: action,
    );
  }

  /// Check if this validator has any rules
  bool get hasRules => validatorType == ValidatorType.jsonSchema;

  /// Get the validator command for collMod
  Map<String, dynamic> toCollModCommand() {
    if (validatorType == ValidatorType.none) {
      return {
        'validator': {},
        'validationLevel': 'off',
      };
    }

    return {
      'validator': jsonSchema,
      'validationLevel': validationLevel.name,
      'validationAction': validationAction.name,
    };
  }
}
