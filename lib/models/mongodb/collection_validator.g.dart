// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'collection_validator.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

CollectionValidator _$CollectionValidatorFromJson(Map<String, dynamic> json) =>
    CollectionValidator(
      collectionName: json['collectionName'] as String,
      validatorType: $enumDecode(_$ValidatorTypeEnumMap, json['validatorType']),
      jsonSchema: json['jsonSchema'] as Map<String, dynamic>?,
      validationLevel:
          $enumDecodeNullable(
            _$ValidationLevelEnumMap,
            json['validationLevel'],
          ) ??
          ValidationLevel.off,
      validationAction:
          $enumDecodeNullable(
            _$ValidationActionEnumMap,
            json['validationAction'],
          ) ??
          ValidationAction.warn,
    );

Map<String, dynamic> _$CollectionValidatorToJson(
  CollectionValidator instance,
) => <String, dynamic>{
  'collectionName': instance.collectionName,
  'validatorType': _$ValidatorTypeEnumMap[instance.validatorType]!,
  'jsonSchema': instance.jsonSchema,
  'validationLevel': _$ValidationLevelEnumMap[instance.validationLevel]!,
  'validationAction': _$ValidationActionEnumMap[instance.validationAction]!,
};

const _$ValidatorTypeEnumMap = {
  ValidatorType.jsonSchema: 'jsonSchema',
  ValidatorType.none: 'none',
};

const _$ValidationLevelEnumMap = {
  ValidationLevel.strict: 'strict',
  ValidationLevel.moderate: 'moderate',
  ValidationLevel.off: 'off',
};

const _$ValidationActionEnumMap = {
  ValidationAction.error: 'error',
  ValidationAction.warn: 'warn',
};
